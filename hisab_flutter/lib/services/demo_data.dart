/// Demo data: three synthetic statements (bundled assets) imported through
/// the normal pipeline, mirroring Hisab/Services/DemoData.swift.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
import 'import_service.dart';

class DemoData {
  static const _files = {
    'assets/demo/demo-gpay.csv': Source.gpay,
    'assets/demo/demo-hdfc.csv': Source.hdfc,
    'assets/demo/demo-idfc.csv': Source.idfc,
  };

  static Future<void> load(ImportService service) async {
    for (final entry in _files.entries) {
      final text = shiftToPresent(await rootBundle.loadString(entry.key));
      final parser = SyntheticCsvParser(source: entry.value);
      final parsed = parser.parse(utf8.encode(text));
      await service.insertParsedDocument(
        parsed: parsed,
        source: entry.value,
        filename: entry.key.split('/').last,
        fileHash: 'demo-${entry.value.rawValue}',
      );
    }
  }

  static final _datePattern = RegExp(r'\d{4}-\d{2}-\d{2}');

  /// The demo statements carry fixed dates. Slide every month forward so the
  /// newest demo month is the current month — which leaves the newest
  /// *complete* demo month on the last complete month relative to today.
  /// Otherwise the demo set silently stops producing insights as time passes:
  /// recurrence wants a series that is still active, and anomalies only look
  /// back 35 days. Port of DemoData.shiftToPresent in Hisab/Services/DemoData.swift.
  ///
  /// Every file is anchored on its own newest date, so the three statements
  /// must keep sharing a newest month (each ends with a `period` line in it) —
  /// that is what makes them all slide by the same number of months.
  static String shiftToPresent(String csv, {DateTime? now}) {
    final matches = _datePattern.allMatches(csv).toList();
    DateTime? newest;
    for (final match in matches) {
      final date = StatementDate.tryParse(match[0]!, 'yyyy-MM-dd');
      if (date == null) continue;
      if (newest == null || date.isAfter(newest)) newest = date;
    }
    if (newest == null) return csv;

    final target = YearMonth.fromDate(now ?? DateTime.now());
    final source = YearMonth.fromDate(newest);
    final shift = (target.year * 12 + target.month) -
        (source.year * 12 + source.month);
    if (shift == 0) return csv;

    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in matches) {
      final date = StatementDate.tryParse(match[0]!, 'yyyy-MM-dd');
      if (date == null) continue;
      buffer.write(csv.substring(cursor, match.start));
      buffer.write(istDayString(_shifted(date, shift)));
      cursor = match.end;
    }
    buffer.write(csv.substring(cursor));
    return buffer.toString();
  }

  /// Same day-of-month in the shifted month, clamped to its length. The demo
  /// statements only ever use days 1–28, so the clamp never actually fires —
  /// which is deliberate: a date on the 29th–31st would land on a different
  /// day-of-month in a shorter month and pull recurrence cadences out of range.
  static DateTime _shifted(DateTime date, int shift) {
    final day = istClock(date).day;
    final month = YearMonth.fromDate(date).advancedBy(shift);
    final length =
        DateTime.utc(month.year, month.month + 1, 1).subtract(const Duration(days: 1)).day;
    return DateTime.utc(month.year, month.month, day < length ? day : length)
        .subtract(istOffset);
  }

  static Future<void> eraseAll(AppDatabase db) async {
    await db.delete(db.storedMatches).go();
    await db.delete(db.storedTransactions).go();
    await db.delete(db.storedDocuments).go();
    await db.delete(db.storedCategoryRules).go();
    await db.delete(db.pinnedMonths).go();
  }
}
