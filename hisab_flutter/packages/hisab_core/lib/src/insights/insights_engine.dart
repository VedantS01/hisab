/// The single entry point the apps call. Port of InsightsEngine.swift.
library;

import '../domain.dart';
import '../year_month.dart';
import 'anomaly_detector.dart';
import 'complete_months.dart';
import 'insight.dart';
import 'insights_config.dart';
import 'recurrence_detector.dart';
import 'trend_detector.dart';

class InsightsEngine {
  static InsightsResult generate({
    required InsightsInput input,
    required InsightsConfig config,
    required Suppressions suppressions,
  }) {
    final completeMonths = CompleteMonths.of(input.documentPeriods);
    final latest = CompleteMonths.latest(input.documentPeriods, input.now);

    var monthDebitTotal = 0;
    if (latest != null) {
      for (final row in input.records) {
        if (row.direction == Direction.debit &&
            YearMonth.fromDate(row.date) == latest) {
          monthDebitTotal += row.amountPaise;
        }
      }
    }

    var trends = <Insight>[];
    var concentrationIDs = <String>{};
    if (latest != null) {
      (trends, concentrationIDs) = TrendDetector.detect(
        records: input.records,
        month: latest,
        completeMonths: completeMonths,
        monthDebitTotalPaise: monthDebitTotal,
        config: config,
      );
    }
    final (recurrences, claimedIDs) = RecurrenceDetector.detect(
      records: input.records,
      now: input.now,
      monthDebitTotalPaise: monthDebitTotal,
      config: config,
    );
    final anomalies = AnomalyDetector.detect(
      records: input.records,
      now: input.now,
      monthDebitTotalPaise: monthDebitTotal,
      config: config,
    );

    // One event, one card.
    final explained = {...claimedIDs, ...concentrationIDs};
    // The two anomaly passes are independent, so a row that is both
    // duplicated and unusually large would produce two cards about one
    // event. "You may have paid twice" is the more actionable reading, so a
    // possible-duplicate card supersedes an outlier on its rows.
    for (final insight in anomalies) {
      if (insight.kind == InsightKind.possibleDuplicate) {
        explained.addAll(insight.evidenceIDs);
      }
    }
    final deduped = [
      for (final insight in anomalies)
        if (insight.kind != InsightKind.outlierAmount ||
            !insight.evidenceIDs.any(explained.contains))
          insight
    ];

    final everything = [...trends, ...recurrences, ...deduped];
    // allIDs covers every card this pass generated, collision-suppressed ones
    // included, so a dismissal survives a suppression that later lifts rather
    // than being pruned while its card is merely hidden.
    final allIDs = {
      for (final i in [...trends, ...recurrences, ...anomalies]) i.id
    };

    final surviving = [
      for (final insight in everything)
        if (!suppressions.dismissedIDs.contains(insight.id) &&
            _passesMute(insight, suppressions))
          insight
    ];

    final committed = [
      for (final i in surviving)
        if (i.kind == InsightKind.committedSpend) i
    ];
    final ranked = [
      for (final i in surviving)
        if (i.kind != InsightKind.committedSpend) i
    ]..sort((l, r) =>
        l.score == r.score ? l.id.compareTo(r.id) : r.score.compareTo(l.score));

    final budget = config.ranker.maxCards - (committed.isEmpty ? 0 : 1);
    final perKind = <InsightKind, int>{};
    final cards = <Insight>[];
    for (final insight in ranked) {
      if (cards.length >= budget) break;
      final used = perKind[insight.kind] ?? 0;
      if (used >= config.ranker.maxPerType) continue;
      perKind[insight.kind] = used + 1;
      cards.add(insight);
    }
    if (committed.isNotEmpty) cards.add(committed.first);
    return InsightsResult(cards: cards, allIDs: allIDs);
  }

  static bool _passesMute(Insight insight, Suppressions suppressions) {
    final mute = insight.mute;
    return switch (mute) {
      MuteMerchant(:final merchantKey) =>
        !suppressions.mutedMerchants.contains(merchantKey),
      MuteCategory(:final category) =>
        !suppressions.mutedCategories.contains(category),
      null => true,
    };
  }
}
