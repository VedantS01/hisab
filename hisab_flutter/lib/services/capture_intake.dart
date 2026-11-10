/// The one door every alert comes in through: Android's notification listener
/// and iOS's "Add Transaction Alert" Shortcuts action both end here. Mirrors
/// the Swift app's `AddTransactionAlertIntent.perform` step for step, because
/// that order is what the System check's outcome line explains to the user.
library;

import 'package:flutter/foundation.dart';
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
import 'capture_prefs.dart';
import 'detections.dart';
import 'import_service.dart';
import 'memo_store.dart';

class IntakeResult {
  final IntakeOutcome outcome;

  /// What Shortcuts says back to the user after the action runs.
  final String dialog;

  const IntakeResult(this.outcome, this.dialog);
}

abstract final class CaptureIntake {
  static Future<IntakeResult> ingest({
    required String text,
    String? note,
    required AppDatabase db,
    required DateTime now,
    AlertExtractor? extractor,
    Future<void> Function(PendingMemo memo)? onCaptured,
  }) async {
    // Unconditional, and BEFORE both the enable gate and the parse: an alert
    // that arrived while capture was off is still an arrival, and health's
    // whole job is to tell "nothing is reaching Hisab" apart from "everything
    // reaches Hisab and none of it parses".
    await CapturePrefs.setLastAttemptAt(now);

    // The Settings toggle has to actually stop capture. A toggle that only
    // silences the notification while memos keep accruing is worse than no
    // toggle — the user believes they switched the feature off.
    if (!await CapturePrefs.isEnabled()) {
      return _done(IntakeOutcome.captureOff, now,
          "Capture is off. Turn it on in Hisab's settings.");
    }

    // An automation whose Alert Text is not wired to Shortcut Input hands
    // over nothing. Saying "no transaction found" would blame the alert.
    if (text.trim().isEmpty) {
      return _done(IntakeOutcome.noText, now,
          "The automation passed no text. In Shortcuts, set Hisab's Alert "
          'Text to Shortcut Input.');
    }

    // The only place the raw text exists. It is not stored, not logged, and
    // goes out of scope with this call.
    final (read, row) = await _read(EmailText.plain(text), now, extractor);
    final memo = read == null || note == null ? read : _withNote(read, note);
    if (memo == null && row == null) {
      return _done(IntakeOutcome.notAPayment, now,
          'No transaction found in that text.');
    }

    final bool memoInserted;
    final bool rowInserted;
    try {
      memoInserted = memo != null && await MemoStore.insert(memo, db: db);
      // Only an alert carrying a bank reference has a row; the content hash
      // (source + reference + direction) is its dedup guard.
      final rowId =
          row == null ? null : await ImportService.insertCapturedAlert(row, db: db);
      rowInserted = rowId != null;
      // A memo for a payment the ledger has — this alert's new row, or the
      // one an earlier capture of it made — is that row's, not a detection.
      if (memo != null && memoInserted && row != null) {
        final txn = rowId ??
            await Detections.rowWith(row.reference!, row.direction, db: db);
        if (txn != null) await Detections.link(memo.captureHash, txn, db: db);
      }
      // No reference: another sighting of a payment already here, or the
      // one row it is, takes it; otherwise it waits in Detections.
      if (memo != null && memoInserted && row == null) {
        await Detections.settle(memo.captureHash, db: db);
      }
    } catch (error) {
      // A store that could not be written is NOT a duplicate. Saying "already
      // logged" would promise the spend is filed when nothing was written,
      // and refreshing lastCaptureAt would paint the broken store healthy.
      debugPrint('capture: save failed (${error.runtimeType})');
      return _done(IntakeOutcome.saveFailed, now,
          "Hisab couldn't save that alert. Nothing was stored.");
    }

    // On a PARSED alert, whether or not it was new — a duplicate is still
    // proof the pipeline works, and the health indicator is about the
    // pipeline.
    await CapturePrefs.setLastCaptureAt(now);
    // Memo and row carry the same amount; the memo's payee is the name the
    // user knows, the row's counterparty the fallback when there is no memo.
    final amount =
        Money.formatPaise(memo?.amountPaise ?? row?.amountPaise ?? 0);
    if (!memoInserted && !rowInserted) {
      return _done(IntakeOutcome.duplicate, now, 'Already logged $amount.');
    }

    // Only on a newly inserted memo: a re-posted alert must not produce a
    // second banner, and a ledger row alone (an account-to-account transfer)
    // has nobody to label.
    if (memo != null && memoInserted) await onCaptured?.call(memo);
    final payee = memo?.payee ?? row?.counterparty ?? '';
    final logged =
        payee.isEmpty ? 'Logged $amount' : 'Logged $amount to $payee';
    return _done(IntakeOutcome.logged, now,
        rowInserted ? '$logged and added it to your ledger.' : '$logged.');
  }

  static Future<IntakeResult> _done(
      IntakeOutcome outcome, DateTime now, String dialog) async {
    await CapturePrefs.record(outcome, now);
    return IntakeResult(outcome, dialog);
  }

  static PendingMemo _withNote(PendingMemo memo, String note) => PendingMemo(
        amountPaise: memo.amountPaise,
        direction: memo.direction,
        payee: memo.payee,
        vpa: memo.vpa,
        accountTail: memo.accountTail,
        date: memo.date,
        capturedAt: memo.capturedAt,
        note: note,
      );

  /// The extractor's memo and ledger row ([AlertCapture]) when it is loaded;
  /// the parser's memo and no row while it loads, if it never does, and if
  /// one extraction throws. An alert the extractor reads as no transaction is
  /// an answer, not a failure — it does not go to the parser.
  static Future<(PendingMemo?, ParsedTransaction?)> _read(
      String text, DateTime now, AlertExtractor? extractor) async {
    if (extractor != null) {
      try {
        final alert = await extractor.extract(text);
        return (
          AlertCapture.memo(alert, receivedAt: now, text: text),
          AlertCapture.ledgerRow(alert, receivedAt: now, text: text),
        );
      } catch (error) {
        // The type only: an error's message could quote the text.
        debugPrint('capture: extraction failed, reading the alert with the '
            'parser (${error.runtimeType})');
      }
    }
    return (AlertParser.parse(text, now), null);
  }
}
