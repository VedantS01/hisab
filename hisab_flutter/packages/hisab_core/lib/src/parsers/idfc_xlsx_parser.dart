/// IDFC FIRST Bank .xlsx statements. Port of IDFCXLSXParser.swift — explicit
/// Debit/Credit columns, running Balance verified, balance-keyed synthetic
/// refs for ref-less rows.
library;

import '../domain.dart';
import '../generic_bank/statement_date.dart';
import '../generic_bank/synthetic_ref.dart';
import '../generic_bank/xlsx_reader.dart';
import 'idfc_common.dart';

class IdfcXlsxParser implements StatementParser {
  @override
  Source get source => Source.idfc;

  const IdfcXlsxParser();

  @override
  bool canParse(List<int> data, String filename) {
    if (data.length < 2 || data[0] != 0x50 || data[1] != 0x4B) return false;
    final workbook = XlsxReader.read(data);
    if (workbook == null) return false;
    return workbook.sharedStrings.contains('STATEMENT OF ACCOUNT') &&
        workbook.sharedStrings.any((s) => s.startsWith('IDFB'));
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final workbook = XlsxReader.read(data);
    if (workbook == null) throw const UnrecognizedFormatException();

    List<Map<String, String>>? rows;
    for (final sheet in workbook.sheets.values) {
      if (sheet.any((r) => r.containsValue('Transaction Date'))) {
        rows = sheet;
        break;
      }
    }
    if (rows == null) throw const UnrecognizedFormatException();
    final headerIndex =
        rows.indexWhere((r) => r.containsValue('Transaction Date'));
    if (headerIndex < 0) throw const UnrecognizedFormatException();
    final header = rows[headerIndex];
    String? column(String title) {
      for (final entry in header.entries) {
        if (entry.value == title) return entry.key;
      }
      return null;
    }

    final dateCol = column('Transaction Date');
    final particularsCol = column('Particulars');
    final debitCol = column('Debit');
    final creditCol = column('Credit');
    final balanceCol = column('Balance');
    if (dateCol == null ||
        particularsCol == null ||
        debitCol == null ||
        creditCol == null ||
        balanceCol == null) {
      throw const UnrecognizedFormatException();
    }

    int? previousBalance;
    final transactions = <ParsedTransaction>[];

    for (final row in rows.skip(headerIndex + 1)) {
      final dateText = row[dateCol];
      final date = dateText == null
          ? null
          : StatementDate.tryParse(dateText, 'dd-MMM-yyyy');
      final particulars = row[particularsCol];
      final balanceText = row[balanceCol];
      final balance = balanceText == null ? null : _paise(balanceText);
      if (date == null || particulars == null || balance == null) continue;

      final debit = row[debitCol] == null ? null : _paise(row[debitCol]!);
      final credit = row[creditCol] == null ? null : _paise(row[creditCol]!);
      Direction direction;
      int amount;
      if (debit != null && credit == null) {
        direction = Direction.debit;
        amount = debit;
      } else if (debit == null && credit != null) {
        direction = Direction.credit;
        amount = credit;
      } else {
        throw MalformedRowException(0, particulars);
      }

      final previous = previousBalance;
      if (previous != null) {
        final expected =
            direction == Direction.debit ? previous - amount : previous + amount;
        if (expected != balance) {
          throw MalformedRowException(0, 'balance chain break at: $particulars');
        }
      }
      previousBalance = balance;

      final (counterparty, reference) = IdfcStatementText.extract(particulars);
      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: amount,
        direction: direction,
        counterparty: counterparty,
        reference: reference ??
            SyntheticRef.make(
                balancePaise: balance, date: date, amountPaise: amount),
        narration: particulars,
      ));
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();

    DatePeriod? declaredPeriod;
    final periodRegex =
        RegExp(r'^(\d{2}-[A-Za-z]{3}-\d{4}) TO (\d{2}-[A-Za-z]{3}-\d{4})$');
    for (final text in workbook.sharedStrings) {
      final match = periodRegex.firstMatch(text);
      if (match == null) continue;
      final start = StatementDate.tryParse(match.group(1)!, 'dd-MMM-yyyy');
      final end = StatementDate.tryParse(match.group(2)!, 'dd-MMM-yyyy');
      if (start == null || end == null) continue;
      declaredPeriod = DatePeriod(start, end);
      break;
    }
    return ParsedDocument(
        source: Source.idfc,
        declaredPeriod: declaredPeriod,
        transactions: transactions);
  }

  /// "303594.0" / "1417816.76" / "1999" → paise, exact. Mirrors the Swift
  /// Decimal-based conversion for raw xlsx numeric cells.
  static int? _paise(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final negative = text.startsWith('-');
    final unsigned = negative ? text.substring(1) : text;
    final parts = unsigned.split('.');
    if (parts.length > 2 || parts[0].isEmpty) return null;
    final rupees = int.tryParse(parts[0]);
    if (rupees == null) return null;
    var fraction = 0;
    if (parts.length == 2 && parts[1].isNotEmpty) {
      var digits = parts[1];
      if (digits.length == 1) digits = '${digits}0';
      if (digits.length > 2) {
        // Round half-even like NSDecimalRound(.plain)? Statement cells carry
        // at most 2 decimals; longer means float noise — round half up.
        final head = int.tryParse(digits.substring(0, 2));
        final next = int.tryParse(digits.substring(2, 3));
        if (head == null || next == null) return null;
        fraction = next >= 5 ? head + 1 : head;
      } else {
        final value = int.tryParse(digits);
        if (value == null) return null;
        fraction = value;
      }
    }
    final paise = rupees * 100 + fraction;
    return negative ? -paise : paise;
  }
}
