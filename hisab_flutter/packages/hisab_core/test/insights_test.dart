import 'dart:io';

import 'package:hisab_core/hisab_core.dart';
import 'package:test/test.dart';

String bundledConfigJson() =>
    File('../../assets/insights/insights-config.json').readAsStringSync();

void main() {
  group('InsightsConfig', () {
    test('bundled config parses with the same values Swift asserts', () {
      final config = InsightsConfig.fromJsonString(bundledConfigJson());
      expect(config.version, 1);
      expect(config.trend.minPct, 25);
      expect(config.trend.minAbsPaise, 50000);
      expect(config.recurrence.minOccurrences, 3);
      expect(config.anomaly.lookbackDays, 35);
      expect(config.ranker.maxCards, 5);
      expect(config.ranker.maxPerType, 3);
    });

    test('bundled config equals the compiled fallback', () {
      expect(InsightsConfig.fromJsonString(bundledConfigJson()),
          InsightsConfig.fallback);
    });
  });

  group('Insight model', () {
    test('insight ids match the digests pinned in Swift', () {
      expect(InsightID.make('trend|Food Delivery|2026-08|40'), 'a84b5c10538a32a7');
      expect(InsightID.make('recurring-new|netflix|64900'), '47007c34745ef802');
      expect(InsightID.make('outlier|txn-42'), '0230759323d235ce');
    });

    test('kind names are the wire names Swift pins', () {
      expect(InsightKind.values.map((k) => k.name).toList(), [
        'trend', 'recurringNew', 'recurringChanged',
        'committedSpend', 'possibleDuplicate', 'outlierAmount',
      ]);
    });

    test('istDaysBetween counts IST calendar days', () {
      final a = DateTime.fromMillisecondsSinceEpoch(1785000000 * 1000, isUtc: true);
      final b = a.add(const Duration(days: 3));
      expect(istDaysBetween(a, b), 3);
      expect(istDaysBetween(b, a), -3);
    });
  });
}
