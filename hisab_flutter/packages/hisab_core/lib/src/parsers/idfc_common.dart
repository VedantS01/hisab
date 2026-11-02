/// IDFC particulars extraction and row reading shared by the XLSX and PDF
/// parsers. Port of IDFCStatementText.extract.
library;

import '../domain.dart';
import '../generic_bank/synthetic_ref.dart';

/// One statement row, amounts in paise: the same in either rendition.
typedef IdfcRow = ({
  DateTime date,
  String particulars,
  int? debit,
  int? credit,
  int balance,
});

class IdfcStatementText {
  /// Exactly one of debit and credit per row, the running balance verified
  /// row to row, balance-keyed synthetic refs for rows with no rail ref.
  static List<ParsedTransaction> transactions(Iterable<IdfcRow> rows) {
    int? previousBalance;
    final transactions = <ParsedTransaction>[];
    for (final row in rows) {
      final Direction direction;
      final int amount;
      if (row.debit != null && row.credit == null) {
        direction = Direction.debit;
        amount = row.debit!;
      } else if (row.debit == null && row.credit != null) {
        direction = Direction.credit;
        amount = row.credit!;
      } else {
        throw MalformedRowException(0, row.particulars);
      }

      final previous = previousBalance;
      if (previous != null) {
        final expected =
            direction == Direction.debit ? previous - amount : previous + amount;
        if (expected != row.balance) {
          throw MalformedRowException(
              0, 'balance chain break at: ${row.particulars}');
        }
      }
      previousBalance = row.balance;

      final (counterparty, reference) = extract(row.particulars);
      transactions.add(ParsedTransaction(
        date: row.date,
        amountPaise: amount,
        direction: direction,
        counterparty: counterparty,
        reference: reference ??
            SyntheticRef.make(
                balancePaise: row.balance, date: row.date, amountPaise: amount),
        narration: row.particulars,
      ));
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();
    return transactions;
  }

  /// Counterparty/reference from the particulars, by transaction rail:
  /// "UPI/DR/<ref>/<name>/…", "NEFT/<ref>/<name>/…", "POS-…/<name>/<ref>/…".
  static (String, String?) extract(String particulars) {
    final parts = particulars.split('/').map((p) => p.trim()).toList();
    if (parts.length >= 4 &&
        parts[0] == 'UPI' &&
        (parts[1] == 'DR' || parts[1] == 'CR')) {
      return (parts[3], parts[2].isEmpty ? null : parts[2]);
    }
    if (parts.length >= 3 &&
        (parts[0] == 'NEFT' || parts[0] == 'IMPS' || parts[0] == 'RTGS')) {
      return (parts[2], parts[1].isEmpty ? null : parts[1]);
    }
    if (parts.length >= 3 && parts[0].startsWith('POS')) {
      final refCandidate = parts[2];
      final ref = refCandidate.isNotEmpty &&
              RegExp(r'^\d+$').hasMatch(refCandidate)
          ? refCandidate
          : null;
      return (parts[1], ref);
    }
    final name = particulars.length > 60
        ? particulars.substring(0, 60).trim()
        : particulars.trim();
    return (name, null);
  }
}
