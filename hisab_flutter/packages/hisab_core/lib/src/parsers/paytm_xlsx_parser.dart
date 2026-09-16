/// Paytm "UPI Statement" .xlsx exports. Port of PaytmXLSXParser.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../year_month.dart';
import '../generic_bank/xlsx_reader.dart';

class PaytmXlsxParser implements StatementParser {
  @override
  Source get source => Source.paytm;

  const PaytmXlsxParser();

  @override
  bool canParse(List<int> data, String filename) {
    if (data.length < 2 || data[0] != 0x50 || data[1] != 0x4B) return false;
    final workbook = XlsxReader.read(data);
    if (workbook == null) return false;
    return workbook.sharedStrings.any((s) => s.contains('Paytm Statement for'));
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final workbook = XlsxReader.read(data);
    if (workbook == null) throw const UnrecognizedFormatException();

    List<Map<String, String>>? table;
    for (final rows in workbook.sheets.values) {
      if (rows.isNotEmpty &&
          rows.first['A'] == 'Date' &&
          rows.first['B'] == 'Time') {
        table = rows;
        break;
      }
    }
    if (table == null) throw const UnrecognizedFormatException();

    final header = table[0];
    String? column(String prefix) {
      for (final entry in header.entries) {
        if (entry.value.startsWith(prefix)) return entry.key;
      }
      return null;
    }

    final dateCol = column('Date');
    final timeCol = column('Time');
    final detailCol = column('Transaction Details');
    final amountCol = column('Amount');
    if (dateCol == null ||
        timeCol == null ||
        detailCol == null ||
        amountCol == null) {
      throw const UnrecognizedFormatException();
    }
    final refCol = column('UPI Ref');
    final accountCol = column('Your Account');
    final otherCol = column('Other Transaction');
    final tagsCol = column('Tags');
    final remarksCol = column('Remarks');

    final transactions = <ParsedTransaction>[];
    for (var index = 1; index < table.length; index++) {
      final row = table[index];
      if (row.isEmpty) continue;
      final dateText = row[dateCol];
      final timeText = row[timeCol];
      final amountText = row[amountCol];
      final detail = row[detailCol];
      final date = (dateText != null && timeText != null)
          ? _parseDateTime(dateText, timeText)
          : null;
      final signedPaise =
          amountText == null ? null : Money.signedPaise(amountText);
      if (date == null ||
          signedPaise == null ||
          signedPaise == 0 ||
          detail == null) {
        final sortedValues = (row.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key)))
            .map((e) => e.value)
            .join(',');
        throw MalformedRowException(index + 1, sortedValues);
      }

      var counterparty = detail;
      for (final prefix in ['Paid to ', 'Received from ', 'Money sent to ']) {
        if (detail.startsWith(prefix)) {
          counterparty = detail.substring(prefix.length);
          break;
        }
      }

      final narrationParts = <String>[detail];
      final other = otherCol == null ? null : row[otherCol];
      if (other != null) narrationParts.add(other);
      final account = accountCol == null ? null : row[accountCol];
      if (account != null) narrationParts.add(account);
      final remarks = remarksCol == null ? null : row[remarksCol];
      if (remarks != null) narrationParts.add(remarks);
      final tags = tagsCol == null ? null : row[tagsCol];
      if (tags != null) narrationParts.add(tags);

      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: signedPaise.abs(),
        direction: signedPaise < 0 ? Direction.debit : Direction.credit,
        counterparty: counterparty,
        reference: refCol == null ? null : row[refCol],
        narration: narrationParts.join(' / '),
      ));
    }
    if (transactions.isEmpty) throw const EmptyDocumentException();

    return ParsedDocument(
        source: Source.paytm,
        declaredPeriod: period(workbook.sharedStrings),
        transactions: transactions);
  }

  /// "dd/MM/yyyy" + "HH:mm:ss" in IST → instant.
  static DateTime? _parseDateTime(String dateText, String timeText) {
    final d = dateText.split('/');
    final t = timeText.split(':');
    if (d.length != 3 || t.length != 3) return null;
    final day = int.tryParse(d[0]);
    final month = int.tryParse(d[1]);
    final year = int.tryParse(d[2]);
    final hour = int.tryParse(t[0]);
    final minute = int.tryParse(t[1]);
    final second = int.tryParse(t[2]);
    if ([day, month, year, hour, minute, second].contains(null)) return null;
    return DateTime.utc(year!, month!, day!, hour!, minute!, second!)
        .subtract(istOffset);
  }

  /// Finds "5 MAR'26 - 4 SEP'26" anywhere in the workbook's strings.
  static DatePeriod? period(List<String> strings) {
    const months = {
      'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
      'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
    };
    final regex = RegExp(
        r"^(\d{1,2}) ([A-Z]{3})'(\d{2}) - (\d{1,2}) ([A-Z]{3})'(\d{2})$");
    for (final raw in strings) {
      final match = regex.firstMatch(raw.trim());
      if (match == null) continue;
      final startMonth = months[match.group(2)];
      final endMonth = months[match.group(5)];
      if (startMonth == null || endMonth == null) continue;
      final start = DateTime.utc(2000 + int.parse(match.group(3)!), startMonth,
              int.parse(match.group(1)!), 0)
          .subtract(istOffset);
      final end = DateTime.utc(2000 + int.parse(match.group(6)!), endMonth,
              int.parse(match.group(4)!), 23, 59)
          .subtract(istOffset);
      return DatePeriod(start, end);
    }
    return null;
  }
}
