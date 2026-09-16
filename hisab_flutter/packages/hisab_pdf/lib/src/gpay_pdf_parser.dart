/// Google Pay "Transaction statement" PDFs over Syncfusion's line stream.
/// Unlike PDFKit (one field per line), Syncfusion merges each row's date,
/// detail, and amount into one visual line:
///
///     03 Mar, 2026 Paid to MERCHANT NAME ₹1,122
///     01:09 PM UPI Transaction ID: 119436467750
///     Paid by HDFC Bank 3293
///
/// Every row carries a UPI Transaction ID, so identity depends only on the
/// (date, amount, direction, reference) captured here.
library;

import 'package:hisab_core/hisab_core.dart';

import 'pdf_text.dart';

class GpayPdfParser implements StatementParser {
  @override
  Source get source => Source.gpay;

  const GpayPdfParser();

  static final _rowRegex = RegExp(
      r'^(\d{2}) ([A-Z][a-z]{2}), (\d{4}) (Paid to|Received from) (.+?) ₹([\d,]+(?:\.\d{1,2})?)$');
  static final _timeRegex = RegExp(r'^(\d{1,2}):(\d{2})\s?(AM|PM)\b');
  static final _refRegex = RegExp(r'UPI Transaction ID: (\d+)');
  static final _periodRegex = RegExp(
      r'(\d{2}) ([A-Za-z]+) (\d{4}) - (\d{2}) ([A-Za-z]+) (\d{4})');

  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  static const _fullMonths = {
    'January': 1, 'February': 2, 'March': 3, 'April': 4, 'May': 5, 'June': 6,
    'July': 7, 'August': 8, 'September': 9, 'October': 10, 'November': 11,
    'December': 12,
  };

  @override
  bool canParse(List<int> data, String filename) {
    if (PdfText.isLocked(data, null)) {
      return filename.toLowerCase().contains('gpay');
    }
    final pages = PdfText.pageTexts(data, null);
    if (pages == null || pages.isEmpty) return false;
    return pages.first.contains('Transaction statement period');
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    List<String>? pages;
    try {
      pages = PdfText.pageTexts(data, password);
    } catch (_) {
      throw const PasswordRequiredException();
    }
    if (pages == null) throw const UnrecognizedFormatException();
    final lines = pages
        .expand((p) => p.split('\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    DatePeriod? declaredPeriod;
    for (final line in lines) {
      final match = _periodRegex.firstMatch(line);
      if (match == null) continue;
      final sm = _fullMonths[match.group(2)];
      final em = _fullMonths[match.group(5)];
      if (sm == null || em == null) continue;
      declaredPeriod = DatePeriod(
        DateTime.utc(int.parse(match.group(3)!), sm, int.parse(match.group(1)!))
            .subtract(istOffset),
        DateTime.utc(int.parse(match.group(6)!), em, int.parse(match.group(4)!))
            .subtract(istOffset),
      );
      break;
    }

    final transactions = <ParsedTransaction>[];
    // Pending row awaiting its time/reference line.
    RegExpMatch? row;
    for (final line in lines) {
      final rowMatch = _rowRegex.firstMatch(line);
      if (rowMatch != null) {
        if (row != null) {
          throw MalformedRowException(0, 'row without time/reference: $line');
        }
        row = rowMatch;
        continue;
      }
      if (row != null) {
        final time = _timeRegex.firstMatch(line);
        final ref = _refRegex.firstMatch(line);
        if (time == null && ref == null) continue; // furniture between rows
        if (time == null || ref == null) {
          throw MalformedRowException(0, line);
        }
        final month = _months[row.group(2)];
        if (month == null) throw MalformedRowException(0, row.group(0)!);
        var hour = int.parse(time.group(1)!) % 12;
        if (time.group(3) == 'PM') hour += 12;
        final date = DateTime.utc(int.parse(row.group(3)!), month,
                int.parse(row.group(1)!), hour, int.parse(time.group(2)!))
            .subtract(istOffset);
        final amount = Money.signedPaise(row.group(6)!);
        if (amount == null || amount <= 0) {
          throw MalformedRowException(0, row.group(0)!);
        }
        final direction =
            row.group(4) == 'Paid to' ? Direction.debit : Direction.credit;
        final name = row.group(5)!;
        final reference = ref.group(1)!;
        transactions.add(ParsedTransaction(
          date: date,
          amountPaise: amount,
          direction: direction,
          counterparty: name,
          reference: reference,
          narration:
              '${row.group(4)} $name / UPI Transaction ID: $reference',
        ));
        row = null;
      }
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();
    return ParsedDocument(
        source: Source.gpay,
        declaredPeriod: declaredPeriod,
        transactions: transactions);
  }
}
