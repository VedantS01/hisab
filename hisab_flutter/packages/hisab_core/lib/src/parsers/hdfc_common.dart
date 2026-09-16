/// HDFC table semantics shared by the TXT, XLS, and PDF renditions.
/// Port of HDFCRow + HDFCStatementTable from HDFCParser.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../generic_bank/statement_date.dart';
import '../generic_bank/synthetic_ref.dart';

class HdfcRow {
  String? dateText;
  String narration;
  String? refText;
  String? withdrawalText;
  String? depositText;
  String? balanceText;

  HdfcRow({
    this.dateText,
    this.narration = '',
    this.refText,
    this.withdrawalText,
    this.depositText,
    this.balanceText,
  });
}

/// Direction from which amount column is filled, verified against the running
/// Closing Balance chain; zero-padded refs normalized to match UPI ids.
class HdfcStatementTable {
  static ParsedDocument parse({
    required List<HdfcRow> rows,
    required int? openingBalancePaise,
    required DatePeriod? period,
  }) {
    var previousBalance = openingBalancePaise;
    final transactions = <ParsedTransaction>[];

    for (final row in rows) {
      final dateText = row.dateText;
      final date =
          dateText == null ? null : StatementDate.tryParse(dateText, 'dd/MM/yy');
      final balanceText = row.balanceText;
      final balance = balanceText == null ? null : Money.signedPaise(balanceText);
      if (date == null || balance == null) {
        throw MalformedRowException(0, row.narration);
      }
      final withdrawal = row.withdrawalText == null
          ? null
          : Money.signedPaise(row.withdrawalText!);
      final deposit =
          row.depositText == null ? null : Money.signedPaise(row.depositText!);
      Direction direction;
      int amount;
      if (withdrawal != null && deposit == null) {
        direction = Direction.debit;
        amount = withdrawal;
      } else if (withdrawal == null && deposit != null) {
        direction = Direction.credit;
        amount = deposit;
      } else {
        throw MalformedRowException(0, 'amount columns ambiguous: ${row.narration}');
      }
      final previous = previousBalance;
      if (previous != null) {
        final expected =
            direction == Direction.debit ? previous - amount : previous + amount;
        if (expected != balance) {
          throw MalformedRowException(0,
              'balance chain break at: ${row.narration} [date=${row.dateText ?? '-'} '
              'w=${row.withdrawalText ?? '-'} d=${row.depositText ?? '-'} '
              'bal=${row.balanceText ?? '-'} prev=$previous]');
        }
      }
      previousBalance = balance;

      final narration = row.narration.trim();
      final reference = normalizedReference(row.refText) ??
          SyntheticRef.make(
              balancePaise: balance, date: date, amountPaise: amount);
      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: amount,
        direction: direction,
        counterparty: counterparty(narration),
        reference: reference,
        narration: narration,
      ));
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();
    return ParsedDocument(
        source: Source.hdfc, declaredPeriod: period, transactions: transactions);
  }

  /// "0000102422789385" → "102422789385"; all zeros / empty → null.
  static String? normalizedReference(String? raw) {
    if (raw == null) return null;
    final stripped = raw.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? null : stripped;
  }

  /// "UPI-<NAME>-<vpa>-…" → NAME; "NEFT CR-<ifsc>-<NAME>-…" → NAME; else head.
  static String counterparty(String narration) {
    final parts = narration.split('-').map((p) => p.trim()).toList();
    if (parts.length >= 2 && parts[0] == 'UPI') return parts[1];
    const rails = ['NEFT CR', 'NEFT DR', 'IMPS', 'RTGS CR', 'RTGS DR', 'ACH C', 'ACH D'];
    if (parts.length >= 3 && rails.contains(parts[0])) return parts[2];
    return narration.length > 60 ? narration.substring(0, 60) : narration;
  }

  /// "Statement From : dd/MM/yyyy To : dd/MM/yyyy" anywhere in the text.
  static DatePeriod? periodIn(String text) {
    final match = RegExp(
            r'Statement From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:\s*(\d{2}/\d{2}/\d{4})')
        .firstMatch(text);
    if (match == null) return null;
    final start = StatementDate.tryParse(match.group(1)!, 'dd/MM/yyyy');
    final end = StatementDate.tryParse(match.group(2)!, 'dd/MM/yyyy');
    if (start == null || end == null) return null;
    return DatePeriod(start, end);
  }

  static int? openingBalanceIn(String text) {
    final match =
        RegExp(r'Opening Balance[^\n]*\n\s*([\d,]+\.\d{2})').firstMatch(text);
    if (match == null) return null;
    return Money.signedPaise(match.group(1)!);
  }
}
