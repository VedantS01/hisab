/// Paytm "UPI Statement" PDFs over Syncfusion's line stream, which merges
/// each row into one visual line ending in the signed amount:
///
///     02 Sep Paid to FirstClub Note: UPIIntent HDFC Bank - - Rs.453
///     7:33 PM
///     UPI ID: firstclub-13003734.payu@indus Tag: 93
///     UPI Ref No: 624536311139 # Groceries
///
/// The date has no year — inferred from the statement period, matching the
/// Swift parser's newest-first tie-breaking.
library;

import 'package:hisab_core/hisab_core.dart';

import 'pdf_text.dart';

class PaytmPdfParser implements StatementParser {
  @override
  Source get source => Source.paytm;

  const PaytmPdfParser();

  static final _rowRegex = RegExp(
      r'^(\d{2}) ([A-Z][a-z]{2}) (.+?) ([+-]) ?Rs\.([\d,]+(?:\.\d{1,2})?)$');
  static final _timeRegex = RegExp(r'^(\d{1,2}):(\d{2})\s?(AM|PM)$');
  static final _refRegex = RegExp(r'UPI Ref No: (\d+)');
  static final _periodRegex =
      RegExp(r"(\d{1,2}) ([A-Z]{3})'(\d{2}) - (\d{1,2}) ([A-Z]{3})'(\d{2})");

  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  static const _upperMonths = {
    'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
    'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
  };

  @override
  bool canParse(List<int> data, String filename) {
    if (PdfText.isLocked(data, null)) {
      return filename.toLowerCase().contains('paytm');
    }
    final pages = PdfText.pageTexts(data, null);
    if (pages == null || pages.isEmpty) return false;
    return pages.first.contains('Paytm Statement for');
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

    DatePeriod? period;
    for (final line in lines) {
      final match = _periodRegex.firstMatch(line);
      if (match == null) continue;
      final sm = _upperMonths[match.group(2)];
      final em = _upperMonths[match.group(5)];
      if (sm == null || em == null) continue;
      period = DatePeriod(
        DateTime.utc(2000 + int.parse(match.group(3)!), sm,
                int.parse(match.group(1)!), 0)
            .subtract(istOffset),
        DateTime.utc(2000 + int.parse(match.group(6)!), em,
                int.parse(match.group(4)!), 23, 59)
            .subtract(istOffset),
      );
      break;
    }
    if (period == null) throw const UnrecognizedFormatException();

    // Collect blocks: a row line plus its follower lines (time, refs).
    final blocks = <(RegExpMatch, List<String>)>[];
    for (final line in lines) {
      final rowMatch = _rowRegex.firstMatch(line);
      if (rowMatch != null) {
        // The summary section has no dd MMM rows, so any match is a real row.
        blocks.add((rowMatch, []));
        continue;
      }
      if (blocks.isNotEmpty) blocks.last.$2.add(line);
    }
    if (blocks.isEmpty) throw const EmptyDocumentException();

    final startYear = YearMonth.fromDate(period.start).year;
    final endYear = YearMonth.fromDate(period.end).year;
    final years = {endYear, startYear}.toList()..sort((a, b) => b.compareTo(a));

    DateTime? previousDate;
    final transactions = <ParsedTransaction>[];

    for (final (row, followers) in blocks) {
      final month = _months[row.group(2)];
      if (month == null) throw MalformedRowException(0, row.group(0)!);
      final day = int.parse(row.group(1)!);

      var hour = 12, minute = 0;
      for (final line in followers) {
        final time = _timeRegex.firstMatch(line);
        if (time != null) {
          hour = int.parse(time.group(1)!) % 12;
          if (time.group(3) == 'PM') hour += 12;
          minute = int.parse(time.group(2)!);
          break;
        }
      }

      // Year inference: the candidate inside the period wins; ties resolve
      // via the statement's newest-first ordering.
      DateTime? date;
      for (final year in years) {
        final candidate =
            DateTime.utc(year, month, day, hour, minute).subtract(istOffset);
        if (candidate.isBefore(period.start) || candidate.isAfter(period.end)) {
          continue;
        }
        if (date == null) {
          date = candidate;
        } else if (previousDate != null &&
            !candidate.isAfter(previousDate) &&
            date.isAfter(previousDate)) {
          date = candidate;
        }
      }
      if (date == null) throw MalformedRowException(0, row.group(0)!);
      previousDate = date;

      final magnitude = Money.signedPaise(row.group(5)!);
      if (magnitude == null || magnitude <= 0) {
        throw MalformedRowException(0, row.group(0)!);
      }
      final direction =
          row.group(4) == '-' ? Direction.debit : Direction.credit;

      String? reference;
      for (final line in followers) {
        final ref = _refRegex.firstMatch(line);
        if (ref != null) {
          reference = ref.group(1);
          break;
        }
      }

      var counterparty = row.group(3)!;
      for (final prefix in ['Paid to ', 'Received from ', 'Money sent to ']) {
        if (counterparty.startsWith(prefix)) {
          counterparty = counterparty.substring(prefix.length);
          break;
        }
      }
      for (final cut in [' Note:', ' Tag:', ' HDFC Bank', ' IDFC FIRST']) {
        final at = counterparty.indexOf(cut);
        if (at > 0) counterparty = counterparty.substring(0, at);
      }

      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: magnitude,
        direction: direction,
        counterparty: counterparty.trim(),
        reference: reference,
        narration: '${row.group(3)} / ${followers.join(' / ')}',
      ));
    }

    return ParsedDocument(
        source: Source.paytm, declaredPeriod: period, transactions: transactions);
  }
}
