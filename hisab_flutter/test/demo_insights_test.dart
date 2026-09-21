// The bundled demo statements have one job beyond looking plausible: whoever
// taps "Load demo data" — a reviewer, Play's pre-launch robots, us — must see
// a full insight strip, today and in two years' time. The month shift is what
// keeps that true, so this runs the real import pipeline (dedup ->
// reconciliation -> self transfers -> categorisation) over the real assets at
// a spread of "today"s and checks every card kind still comes out.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/demo_data.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/queries.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';

const _demoFiles = {
  'demo-gpay.csv': Source.gpay,
  'demo-hdfc.csv': Source.hdfc,
  'demo-idfc.csv': Source.idfc,
};

/// Everything the detectors produce, before the ranker's cap.
Future<(List<Insight> generated, InsightsResult strip)> run(DateTime now) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final service = ImportService(
      db: db, resolver: ImportResolver(registry: liveRegistry(), specs: const []));
  final ruleset = Ruleset.fromJsonString(
      File('assets/rulesets/india-default.json').readAsStringSync());
  final config = InsightsConfig.fromJsonString(
      File('assets/insights/insights-config.json').readAsStringSync());

  for (final entry in _demoFiles.entries) {
    final text = DemoData.shiftToPresent(
        File('assets/demo/${entry.key}').readAsStringSync(),
        now: now);
    await service.importBytes(
        data: utf8.encode(text),
        filename: entry.key,
        overrideSource: entry.value);
  }

  final rules = await Queries.categoryRules(db, ruleset);
  final records = Queries.insightRecords(
      await db.select(db.storedTransactions).get(),
      await db.select(db.storedMatches).get(),
      rules);
  final periods =
      Queries.insightPeriods(await db.select(db.storedDocuments).get());

  final latest = CompleteMonths.latest(periods, now);
  expect(latest, isNotNull, reason: 'demo data has no complete month');
  expect(latest, YearMonth.fromDate(now).advancedBy(-1),
      reason: 'the newest complete demo month should be last month');

  var monthDebit = 0;
  for (final r in records) {
    if (r.direction == Direction.debit &&
        YearMonth.fromDate(r.date) == latest) {
      monthDebit += r.amountPaise;
    }
  }

  final generated = <Insight>[
    ...TrendDetector.detect(
      records: records,
      month: latest!,
      completeMonths: CompleteMonths.of(periods),
      monthDebitTotalPaise: monthDebit,
      config: config,
    ).$1,
    ...RecurrenceDetector.detect(
      records: records,
      now: now,
      monthDebitTotalPaise: monthDebit,
      config: config,
    ).$1,
    ...AnomalyDetector.detect(
      records: records,
      now: now,
      monthDebitTotalPaise: monthDebit,
      config: config,
    ),
  ];
  final strip = InsightsEngine.generate(
      input: InsightsInput(records: records, documentPeriods: periods, now: now),
      config: config,
      suppressions: const Suppressions());
  return (generated, strip);
}

void main() {
  // A year's worth of month lengths, month starts and month ends — the shift
  // clamps day-of-month, and the anomaly window only looks back 35 days.
  final days = [
    DateTime.utc(2026, 9, 21),
    DateTime.utc(2026, 10, 1),
    DateTime.utc(2026, 10, 31),
    DateTime.utc(2027, 2, 28),
    DateTime.utc(2027, 3, 1),
    DateTime.utc(2027, 3, 31),
    DateTime.utc(2028, 3, 15), // leap year
    DateTime.utc(2028, 12, 31),
  ];

  for (final now in days) {
    test('demo data produces every insight kind on ${istDayString(now)}',
        () async {
      final (generated, strip) = await run(now);

      for (final kind in InsightKind.values) {
        expect(generated.map((i) => i.kind), contains(kind),
            reason: 'no $kind card from the demo statements');
      }

      expect(strip.cards.length, 5);
      expect(strip.cards.last.kind, InsightKind.committedSpend,
          reason: 'committed spend is pinned last');
      expect(strip.cards.where((c) => c.kind == InsightKind.committedSpend),
          hasLength(1));
      // Copy is generated in core, so it is identical on both platforms and
      // must not drift with the calendar.
      expect(strip.cards.map((c) => '${c.kind.name}|${c.headline}').toList(), [
        'outlierAmount|Blue Tokai: ₹1,250.00',
        'trend|Food Delivery: ₹3,420.00',
        'recurringNew|New recurring: Netflix',
        'possibleDuplicate|Zomato: ₹450.00 ×2',
        'committedSpend|₹14,149.00 per month committed',
      ]);
    });
  }
}
