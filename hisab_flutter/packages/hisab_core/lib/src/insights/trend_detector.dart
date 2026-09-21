/// Category month-over-average deltas. Port of TrendDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';

class TrendDetector {
  static (List<Insight>, Set<String>) detect({
    required List<InsightRecord> records,
    required YearMonth month,
    required Set<YearMonth> completeMonths,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.trend;
    final weight = config.ranker.weights[InsightKind.trend.name] ?? 0;

    final window = <YearMonth>[];
    var cursor = month.advancedBy(-1);
    var steps = 0;
    while (window.length < settings.windowMonths && steps < 24) {
      if (completeMonths.contains(cursor)) window.add(cursor);
      cursor = cursor.advancedBy(-1);
      steps++;
    }
    if (window.isEmpty) return (<Insight>[], <String>{});
    final windowSet = window.toSet();

    final currentRows = <String, List<InsightRecord>>{};
    final baseline = <String, int>{};
    for (final row in records) {
      if (row.direction != Direction.debit) continue;
      final rowMonth = YearMonth.fromDate(row.date);
      if (rowMonth == month) {
        currentRows.putIfAbsent(row.category, () => []).add(row);
      } else if (windowSet.contains(rowMonth)) {
        baseline[row.category] = (baseline[row.category] ?? 0) + row.amountPaise;
      }
    }

    final insights = <Insight>[];
    final concentrationIDs = <String>{};
    // Sorted so output order never depends on map iteration order.
    for (final category in currentRows.keys.toList()..sort()) {
      final rows = currentRows[category]!;
      final currentTotal = rows.fold<int>(0, (a, r) => a + r.amountPaise);
      final baselineSum = baseline[category] ?? 0;
      if (baselineSum <= 0) continue;
      final average = baselineSum ~/ window.length;
      if (average <= 0) continue;
      final delta = currentTotal - average;
      final pct = delta * 100 ~/ average;
      if (pct.abs() < settings.minPct || delta.abs() < settings.minAbsPaise) {
        continue;
      }

      var detail = pct >= 0
          ? 'up $pct% vs your ${window.length}-month average'
          : 'down ${-pct}% vs your ${window.length}-month average';
      // Share of the month's category spend, not of the delta: a single
      // purchase clears most modest deltas, so share-of-delta would call
      // nearly every rise "driven by one payment".
      if (delta > 0) {
        final driver =
            rows.reduce((a, b) => a.amountPaise >= b.amountPaise ? a : b);
        if (driver.amountPaise * 100 >= currentTotal * settings.concentrationPct) {
          detail += ' — driven by one ${Money.formatPaise(driver.amountPaise)}'
              ' payment to ${driver.merchant}';
          concentrationIDs.add(driver.id);
        }
      }

      final magnitude = delta.abs() *
          1000 ~/
          (monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1);
      insights.add(Insight(
        id: InsightID.make('trend|$category|$month|$pct'),
        kind: InsightKind.trend,
        headline: '$category: ${Money.formatPaise(currentTotal)}',
        detail: detail,
        evidenceIDs: [for (final r in rows) r.id]..sort(),
        score: magnitude * weight,
        mute: MuteCategory(category),
      ));
    }
    return (insights, concentrationIDs);
  }
}
