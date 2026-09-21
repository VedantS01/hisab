/// Possible duplicates and amount outliers. Port of AnomalyDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';
import 'recurrence_detector.dart';

class AnomalyDetector {
  static List<Insight> detect({
    required List<InsightRecord> records,
    required DateTime now,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.anomaly;
    final weights = config.ranker.weights;
    final debits = [
      for (final r in records)
        if (r.direction == Direction.debit) r
    ];
    final recent = [
      for (final r in debits)
        if (!r.date.isAfter(now) &&
            istDaysBetween(r.date, now) <= settings.lookbackDays)
          r
    ];
    if (recent.isEmpty) return const [];

    final insights = <Insight>[];
    final denominator = monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1;

    final buckets = <String, List<InsightRecord>>{};
    for (final row in recent) {
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      buckets
          .putIfAbsent(
              '$key|${istDayString(row.date)}|${row.amountPaise}', () => [])
          .add(row);
    }
    for (final bucketKey in buckets.keys.toList()..sort()) {
      final members = buckets[bucketKey]!..sort((a, b) => a.id.compareTo(b.id));
      if (members.length < 2) continue;
      if (members.every((m) => hasClockTime(m.date))) {
        final times = [for (final m in members) m.date]..sort();
        var close = false;
        for (var i = 1; i < times.length; i++) {
          if (times[i].difference(times[i - 1]).inSeconds <=
              settings.duplicateWindowMinutes * 60) {
            close = true;
          }
        }
        if (!close) continue;
      }
      final sample = members.first;
      final merchantKey = SuggestionEngine.normalize(sample.merchant);
      final magnitude = sample.amountPaise * 1000 ~/ denominator;
      insights.add(Insight(
        id: InsightID.make(
            'duplicate|${members.map((m) => m.id).join(',')}'),
        kind: InsightKind.possibleDuplicate,
        headline: '${sample.merchant}: ${Money.formatPaise(sample.amountPaise)}'
            ' ×${members.length}',
        detail:
            '${members.length} identical payments on ${dayLabel(sample.date)}',
        evidenceIDs: [for (final m in members) m.id],
        score: magnitude * (weights[InsightKind.possibleDuplicate.name] ?? 0),
        mute: MuteMerchant(merchantKey),
      ));
    }

    final ordered = List.of(recent)..sort((a, b) => a.id.compareTo(b.id));
    for (final row in ordered) {
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      final priors = [
        for (final d in debits)
          if (SuggestionEngine.normalize(d.merchant) == key &&
              d.date.isBefore(row.date))
            d
      ];
      if (priors.length < settings.minPriors) continue;
      final typical =
          RecurrenceDetector.median([for (final p in priors) p.amountPaise]);
      if (typical <= 0) continue;
      if (row.amountPaise < typical * settings.outlierMultiple ||
          row.amountPaise < settings.outlierMinPaise) {
        continue;
      }
      final magnitude = row.amountPaise * 1000 ~/ denominator;
      insights.add(Insight(
        id: InsightID.make('outlier|${row.id}'),
        kind: InsightKind.outlierAmount,
        headline: '${row.merchant}: ${Money.formatPaise(row.amountPaise)}',
        detail: 'about ${row.amountPaise ~/ typical}× your usual '
            '${Money.formatPaise(typical)}',
        evidenceIDs: [row.id],
        score: magnitude * (weights[InsightKind.outlierAmount.name] ?? 0),
        mute: MuteMerchant(key),
      ));
    }
    return insights;
  }

  /// Statement rows without a time land on IST midnight; payment-app rows
  /// carry a real clock time.
  static bool hasClockTime(DateTime date) {
    final c = istClock(date);
    return c.hour != 0 || c.minute != 0 || c.second != 0;
  }

  static String dayLabel(DateTime date) => istDayLabel(date);
}
