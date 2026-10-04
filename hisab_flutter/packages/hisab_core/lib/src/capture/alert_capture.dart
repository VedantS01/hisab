/// What capture stores from one extracted alert. Port of AlertCapture.swift.
///
/// - A **memo**, the labelling channel, when the alert names someone to label:
///   a payee or a VPA. A counterparty that is only an account number would
///   normalize to the same rule key for every transfer, so it gets no memo.
/// - A **ledger row** when the alert carries a payment-rail reference (UPI
///   RRN, IMPS ref, NEFT/RTGS UTR). The reference is what lets the row join
///   content-hash dedup (a second alert for the same payment collapses into it)
///   and reconcile against the statement row that later confirms it. Alerts
///   without one stay memos, as in 1.3.0: nothing unreferenced enters the ledger.
///
/// Pure, so both cores pin it with one fixture (`alert-capture.json`).
library;

import '../domain.dart';
import '../extractor/extracted_alert.dart';
import '../year_month.dart';
import 'pending_memo.dart';

class AlertCapture {
  AlertCapture._();

  static PendingMemo? memo(ExtractedAlert alert, {required DateTime receivedAt}) {
    final direction = alert.direction;
    final amount = alert.amountPaise;
    final payee = _nonEmpty(alert.payee) ?? _nonEmpty(alert.vpa);
    if (!alert.isTransaction ||
        direction == null ||
        amount == null ||
        amount <= 0 ||
        payee == null) {
      return null;
    }
    return PendingMemo(
      amountPaise: amount,
      direction: direction,
      payee: payee,
      vpa: _nonEmpty(alert.vpa),
      accountTail: _nonEmpty(alert.ownAccountTail),
      date: date(alert.dateIso, receivedAt: receivedAt),
      capturedAt: receivedAt,
    );
  }

  static ParsedTransaction? ledgerRow(ExtractedAlert alert,
      {required DateTime receivedAt}) {
    final direction = alert.direction;
    final amount = alert.amountPaise;
    final reference = _nonEmpty(alert.ref);
    if (!alert.isTransaction ||
        direction == null ||
        amount == null ||
        amount <= 0 ||
        reference == null) {
      return null;
    }
    final accountTail = _nonEmpty(alert.counterpartyAccountTail);
    final counterparty = _nonEmpty(alert.payee) ??
        _nonEmpty(alert.vpa) ??
        (accountTail == null ? null : 'A/c $accountTail') ??
        '';
    // Rules match "counterparty narration": carrying the VPA here lets a
    // VPA rule learned from a memo categorize the ledger row too.
    return ParsedTransaction(
      date: date(alert.dateIso, receivedAt: receivedAt),
      amountPaise: amount,
      direction: direction,
      counterparty: counterparty,
      reference: reference,
      narration: _nonEmpty(alert.vpa) ?? '',
    );
  }

  /// The transaction's IST day. `yyyy-MM-dd` as written; `--MM-dd` (no year
  /// in the alert) in the latest year that does not put it after the day the
  /// alert arrived; absent or impossible (29 Feb in a common year) falls back
  /// to the arrival time.
  static DateTime date(String? iso, {required DateTime receivedAt}) {
    if (iso == null) return receivedAt;
    final parts = iso.split('-');
    if (iso.startsWith('--') && parts.length == 4) {
      final month = _int(parts[2]);
      final day = _int(parts[3]);
      if (month != null && day != null) {
        final received = istClock(receivedAt);
        final isLater = month > received.month ||
            (month == received.month && day > received.day);
        return ist(isLater ? received.year - 1 : received.year, month, day) ??
            receivedAt;
      }
    }
    if (parts.length == 3) {
      final year = _int(parts[0]);
      final month = _int(parts[1]);
      final day = _int(parts[2]);
      if (year != null && month != null && day != null) {
        return ist(year, month, day) ?? receivedAt;
      }
    }
    return receivedAt;
  }

  /// Midnight IST of a valid calendar day, or null. `DateTime` silently rolls
  /// 29 Feb 2025 into 1 Mar, so the fields are checked on the way back.
  static DateTime? ist(int year, int month, int day) {
    final date = DateTime.utc(year, month, day).subtract(istOffset);
    final back = istClock(date);
    return back.year == year && back.month == month && back.day == day
        ? date
        : null;
  }

  /// Swift's `Int(String)`: optional sign and decimal digits, nothing else —
  /// `int.tryParse` would also take whitespace and a `0x` prefix.
  static int? _int(String s) =>
      RegExp(r'^[+-]?[0-9]+$').hasMatch(s) ? int.tryParse(s) : null;

  static String? _nonEmpty(String? s) => s == null || s.isEmpty ? null : s;
}
