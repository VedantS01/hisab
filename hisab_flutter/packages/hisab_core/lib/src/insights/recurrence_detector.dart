/// Repeating payments: rent, SIPs, EMIs, subscriptions.
/// Port of RecurrenceDetector.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';
import 'insight.dart';
import 'insights_config.dart';

class RecurrenceDetector {
  static List<RecurringSeries> series({
    required List<InsightRecord> records,
    required DateTime now,
    required InsightsConfig config,
  }) {
    final settings = config.recurrence;
    final groups = <String, List<InsightRecord>>{};
    for (final row in records) {
      if (row.direction != Direction.debit) continue;
      final key = SuggestionEngine.normalize(row.merchant);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(row);
    }

    final result = <RecurringSeries>[];
    for (final key in groups.keys.toList()..sort()) {
      // Date, then id: neither platform's sort is stable, so same-day
      // payments to one merchant need an explicit total order for both
      // cores to emit transactionIDs in the same sequence.
      final members = groups[key]!
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          return d != 0 ? d : a.id.compareTo(b.id);
        });
      if (members.length < settings.minOccurrences) continue;

      final gaps = <int>[];
      for (var i = 1; i < members.length; i++) {
        gaps.add(istDaysBetween(members[i - 1].date, members[i].date));
      }
      final medianGap = median(gaps);
      final Cadence cadence;
      if (medianGap >= settings.monthlyMinDays &&
          medianGap <= settings.monthlyMaxDays) {
        cadence = Cadence.monthly;
      } else if (medianGap >= settings.weeklyMinDays &&
          medianGap <= settings.weeklyMaxDays) {
        cadence = Cadence.weekly;
      } else {
        continue;
      }

      final medianAmount = median([for (final m in members) m.amountPaise]);
      if (medianAmount <= 0) continue;
      final stable = [
        for (final m in members)
          if ((m.amountPaise - medianAmount).abs() * 100 <=
              medianAmount * settings.amountSpreadPct)
            m
      ];
      if (stable.length < settings.minOccurrences) continue;

      final lastSeen = members.last.date;
      final cadenceDays = cadence == Cadence.monthly
          ? settings.monthlyMaxDays
          : settings.weeklyMaxDays;
      if (istDaysBetween(lastSeen, now) >
          cadenceDays * settings.activeWithinCadences) {
        continue;
      }

      // Most common raw spelling; ties resolve alphabetically.
      final rawCounts = <String, int>{};
      for (final m in members) {
        rawCounts[m.merchant] = (rawCounts[m.merchant] ?? 0) + 1;
      }
      var display = key;
      var bestCount = -1;
      rawCounts.forEach((raw, count) {
        if (count > bestCount ||
            (count == bestCount && raw.compareTo(display) < 0)) {
          display = raw;
          bestCount = count;
        }
      });

      result.add(RecurringSeries(
        merchantKey: key,
        displayMerchant: display,
        cadence: cadence,
        medianPaise: medianAmount,
        monthlyEquivalentPaise:
            cadence == Cadence.monthly ? medianAmount : medianAmount * 52 ~/ 12,
        firstSeen: members.first.date,
        lastSeen: lastSeen,
        count: members.length,
        transactionIDs: [for (final m in members) m.id],
      ));
    }
    return result;
  }

  static (List<Insight>, Set<String>) detect({
    required List<InsightRecord> records,
    required DateTime now,
    required int monthDebitTotalPaise,
    required InsightsConfig config,
  }) {
    final settings = config.recurrence;
    final weights = config.ranker.weights;
    final found = series(records: records, now: now, config: config);
    if (found.isEmpty) return (<Insight>[], <String>{});

    final insights = <Insight>[];
    final claimed = <String>{};
    final newCutoff =
        YearMonth.fromDate(now).advancedBy(-settings.newWithinMonths);
    final denominator = monthDebitTotalPaise > 1 ? monthDebitTotalPaise : 1;

    for (final entry in found) {
      claimed.addAll(entry.transactionIDs);
      final cadenceWord =
          entry.cadence == Cadence.monthly ? 'per month' : 'per week';
      final firstMonth = YearMonth.fromDate(entry.firstSeen);

      if (firstMonth.compareTo(newCutoff) >= 0) {
        final magnitude = entry.monthlyEquivalentPaise * 1000 ~/ denominator;
        insights.add(Insight(
          id: InsightID.make(
              'recurring-new|${entry.merchantKey}|${entry.medianPaise}'),
          kind: InsightKind.recurringNew,
          headline: 'New recurring: ${entry.displayMerchant}',
          detail: '${Money.formatPaise(entry.medianPaise)} $cadenceWord'
              ' since ${firstMonth.displayName}',
          evidenceIDs: entry.transactionIDs,
          score: magnitude * (weights[InsightKind.recurringNew.name] ?? 0),
          mute: MuteMerchant(entry.merchantKey),
        ));
        continue; // a brand-new series can't also be "changed"
      }

      // Debits only: the median is a debit-only figure, so the payment
      // measured against it must be one too — a refund sharing the
      // merchant key would otherwise drive the "usually" sentence.
      final sameMerchant = [
        for (final r in records)
          if (r.direction == Direction.debit &&
              SuggestionEngine.normalize(r.merchant) == entry.merchantKey)
            r
      ];
      if (sameMerchant.isEmpty) continue;
      final latest =
          sameMerchant.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
      final drift = (latest.amountPaise - entry.medianPaise).abs();
      if (drift * 100 >= entry.medianPaise * settings.changedPct) {
        final magnitude = drift * 1000 ~/ denominator;
        insights.add(Insight(
          id: InsightID.make(
              'recurring-changed|${entry.merchantKey}|${latest.amountPaise}'),
          kind: InsightKind.recurringChanged,
          headline:
              '${entry.displayMerchant}: ${Money.formatPaise(latest.amountPaise)}',
          detail: 'usually ${Money.formatPaise(entry.medianPaise)} $cadenceWord',
          evidenceIDs: entry.transactionIDs,
          score: magnitude * (weights[InsightKind.recurringChanged.name] ?? 0),
          mute: MuteMerchant(entry.merchantKey),
        ));
      }
    }

    if (found.length >= 2) {
      final total = found.fold<int>(0, (a, s) => a + s.monthlyEquivalentPaise);
      insights.add(Insight(
        id: InsightID.make('committed|${found.length}|$total'),
        kind: InsightKind.committedSpend,
        headline: '${Money.formatPaise(total)} per month committed',
        detail: 'across ${found.length} recurring payments',
        evidenceIDs: [for (final s in found) ...s.transactionIDs],
        series: found,
        score: 0, // pinned last by the ranker
        mute: null,
      ));
    }
    return (insights, claimed);
  }

  /// Lower median of a sorted copy; must match Swift exactly.
  static int median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = List.of(values)..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }
}
