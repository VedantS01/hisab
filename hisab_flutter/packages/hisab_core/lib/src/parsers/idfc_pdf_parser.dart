/// IDFC FIRST Bank PDF statements. Takes its positioned text from [read]
/// rather than the shared PDF hooks: Syncfusion loses glyphs in this
/// statement's font ("UPI/D/60643614627" for "UPI/DR/606435614627"), so the
/// parser is registered only where a faithful reader exists (PDFKit, on iOS).
/// The layout table carries the same rows and particulars as the XLSX, so both
/// files of one statement import as the same transactions.
library;

import '../domain.dart';
import '../generic_bank/statement_date.dart';
import '../generic_bank/statement_layout.dart';
import '../money.dart';
import 'idfc_common.dart';

class IdfcPdfParser implements StatementParser {
  /// Every page's positioned text for these bytes, or null when unread.
  final List<List<TextFragment>>? Function(List<int> data) read;

  const IdfcPdfParser(this.read);

  @override
  Source get source => Source.idfc;

  @override
  bool canParse(List<int> data, String filename) {
    if (data.length < 4 || String.fromCharCodes(data.take(4)) != '%PDF') return false;
    final pages = read(data);
    if (pages == null || pages.isEmpty) return false;
    final lines = _lines(pages.first);
    return lines.contains('STATEMENT OF ACCOUNT') &&
        lines.any(RegExp(r'^IFSC\s*:\s*IDFB0').hasMatch);
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final pages = read(data);
    if (pages == null) throw const UnrecognizedFormatException();
    final table = StatementLayout.table(pages);
    if (table == null) throw const UnrecognizedFormatException();
    final headerIndex = table.rows.indexWhere(
        (r) => r.contains('Particulars') && r.contains('Balance'));
    if (headerIndex < 0) throw const UnrecognizedFormatException();
    final header = table.rows[headerIndex];
    int column(List<String> titles) => header.indexWhere(titles.contains);

    final dateCol = column(['Date', 'Transaction Date']);
    final particularsCol = column(['Particulars']);
    final debitCol = column(['Debit']);
    final creditCol = column(['Credit']);
    final balanceCol = column(['Balance']);
    if (dateCol < 0 || debitCol < 0 || creditCol < 0) {
      throw const UnrecognizedFormatException();
    }

    final transactions = IdfcStatementText.transactions([
      for (final row in table.rows.skip(headerIndex + 1))
        if (_row(row, dateCol, particularsCol, debitCol, creditCol, balanceCol)
            case final read?)
          read,
    ]);

    DatePeriod? declaredPeriod;
    final periodRegex = RegExp(
        r'^STATEMENT PERIOD : (\d{4}-\d{2}-\d{2}) TO (\d{4}-\d{2}-\d{2})$');
    for (final line in _lines(pages.first)) {
      final match = periodRegex.firstMatch(line);
      if (match == null) continue;
      final start = StatementDate.tryParse(match.group(1)!, 'yyyy-MM-dd');
      final end = StatementDate.tryParse(match.group(2)!, 'yyyy-MM-dd');
      if (start != null && end != null) declaredPeriod = DatePeriod(start, end);
      break;
    }
    return ParsedDocument(
        source: Source.idfc,
        declaredPeriod: declaredPeriod,
        transactions: transactions);
  }

  /// A page's text as printed lines: fragments sharing a baseline, left to
  /// right. The reader may cut a line at wide gaps ("STATEMENT PERIOD" |
  /// ":" | "2026-03-01 TO 2026-08-31").
  static List<String> _lines(List<TextFragment> page) {
    final byLine = <int, List<TextFragment>>{};
    for (final f in page) {
      (byLine[f.minY.round()] ??= []).add(f);
    }
    return [
      for (final line in byLine.values)
        (line..sort((a, b) => a.minX.compareTo(b.minX)))
            .map((f) => f.text.trim())
            .join(' ')
    ];
  }

  static IdfcRow? _row(List<String> row, int dateCol, int particularsCol,
      int debitCol, int creditCol, int balanceCol) {
    String? cell(int col) {
      final text = col < row.length ? row[col].trim() : '';
      return text.isEmpty ? null : text;
    }

    final dateText = cell(dateCol);
    final date =
        dateText == null ? null : StatementDate.tryParse(dateText, 'dd-MMM-yyyy');
    // The PDF wraps Particulars after a "/" or "-"; the layout joins wrapped
    // lines with a space where the XLSX has none. (On the real sample this
    // restores 160 of 161 narrations; the miss printed "/ " itself.)
    final particulars =
        cell(particularsCol)?.replaceAll('/ ', '/').replaceAll('- ', '-');
    final balanceText = cell(balanceCol);
    final balance = balanceText == null ? null : Money.signedPaise(balanceText);
    if (date == null || particulars == null || balance == null) return null;
    final debit = cell(debitCol);
    final credit = cell(creditCol);
    return (
      date: date,
      particulars: particulars,
      debit: debit == null ? null : Money.signedPaise(debit),
      credit: credit == null ? null : Money.signedPaise(credit),
      balance: balance,
    );
  }
}
