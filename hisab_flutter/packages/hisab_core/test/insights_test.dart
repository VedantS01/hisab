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

      // IST has no DST, so an exact day-multiple offset can't distinguish
      // calendar-day truncation from a naive elapsed-seconds/86400 divide.
      // These pin actual IST wall-clock instants to rule that out.
      // 2026-08-03 23:00 IST -> 2026-08-04 01:00 IST: 2 hours elapsed, but
      // it crosses an IST midnight, so it must count as 1 day.
      final crossMidnightBefore =
          DateTime.fromMillisecondsSinceEpoch(1785778200 * 1000, isUtc: true);
      final crossMidnightAfter =
          DateTime.fromMillisecondsSinceEpoch(1785785400 * 1000, isUtc: true);
      expect(istDaysBetween(crossMidnightBefore, crossMidnightAfter), 1);
      expect(istDaysBetween(crossMidnightAfter, crossMidnightBefore), -1);

      // 2026-08-04 00:30 IST -> 2026-08-04 23:30 IST: 23 hours elapsed but
      // stays inside one IST calendar day, so it must count as 0 days.
      final sameDayEarly =
          DateTime.fromMillisecondsSinceEpoch(1785783600 * 1000, isUtc: true);
      final sameDayLate =
          DateTime.fromMillisecondsSinceEpoch(1785866400 * 1000, isUtc: true);
      expect(istDaysBetween(sameDayEarly, sameDayLate), 0);
    });
  });
}
