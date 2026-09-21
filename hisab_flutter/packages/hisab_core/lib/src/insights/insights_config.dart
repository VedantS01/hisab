/// Tunable thresholds for the insight detectors. Port of
/// InsightsConfig.swift; the bundled JSON is the same file, synced by
/// tool/sync_assets.sh.
library;

import 'dart:convert';

class TrendConfig {
  final int minPct;
  final int minAbsPaise;
  final int windowMonths;
  final int concentrationPct;
  const TrendConfig({
    required this.minPct,
    required this.minAbsPaise,
    required this.windowMonths,
    required this.concentrationPct,
  });

  factory TrendConfig.fromJson(Map<String, dynamic> j) => TrendConfig(
        minPct: j['minPct'] as int,
        minAbsPaise: j['minAbsPaise'] as int,
        windowMonths: j['windowMonths'] as int,
        concentrationPct: j['concentrationPct'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is TrendConfig &&
      other.minPct == minPct &&
      other.minAbsPaise == minAbsPaise &&
      other.windowMonths == windowMonths &&
      other.concentrationPct == concentrationPct;

  @override
  int get hashCode =>
      Object.hash(minPct, minAbsPaise, windowMonths, concentrationPct);
}

class RecurrenceConfig {
  final int minOccurrences;
  final int monthlyMinDays;
  final int monthlyMaxDays;
  final int weeklyMinDays;
  final int weeklyMaxDays;
  final int amountSpreadPct;
  final int changedPct;
  final int newWithinMonths;
  final int activeWithinCadences;
  const RecurrenceConfig({
    required this.minOccurrences,
    required this.monthlyMinDays,
    required this.monthlyMaxDays,
    required this.weeklyMinDays,
    required this.weeklyMaxDays,
    required this.amountSpreadPct,
    required this.changedPct,
    required this.newWithinMonths,
    required this.activeWithinCadences,
  });

  factory RecurrenceConfig.fromJson(Map<String, dynamic> j) => RecurrenceConfig(
        minOccurrences: j['minOccurrences'] as int,
        monthlyMinDays: j['monthlyMinDays'] as int,
        monthlyMaxDays: j['monthlyMaxDays'] as int,
        weeklyMinDays: j['weeklyMinDays'] as int,
        weeklyMaxDays: j['weeklyMaxDays'] as int,
        amountSpreadPct: j['amountSpreadPct'] as int,
        changedPct: j['changedPct'] as int,
        newWithinMonths: j['newWithinMonths'] as int,
        activeWithinCadences: j['activeWithinCadences'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is RecurrenceConfig &&
      other.minOccurrences == minOccurrences &&
      other.monthlyMinDays == monthlyMinDays &&
      other.monthlyMaxDays == monthlyMaxDays &&
      other.weeklyMinDays == weeklyMinDays &&
      other.weeklyMaxDays == weeklyMaxDays &&
      other.amountSpreadPct == amountSpreadPct &&
      other.changedPct == changedPct &&
      other.newWithinMonths == newWithinMonths &&
      other.activeWithinCadences == activeWithinCadences;

  @override
  int get hashCode => Object.hash(minOccurrences, monthlyMinDays, monthlyMaxDays,
      weeklyMinDays, weeklyMaxDays, amountSpreadPct, changedPct,
      newWithinMonths, activeWithinCadences);
}

class AnomalyConfig {
  final int outlierMultiple;
  final int outlierMinPaise;
  final int minPriors;
  final int lookbackDays;
  final int duplicateWindowMinutes;
  const AnomalyConfig({
    required this.outlierMultiple,
    required this.outlierMinPaise,
    required this.minPriors,
    required this.lookbackDays,
    required this.duplicateWindowMinutes,
  });

  factory AnomalyConfig.fromJson(Map<String, dynamic> j) => AnomalyConfig(
        outlierMultiple: j['outlierMultiple'] as int,
        outlierMinPaise: j['outlierMinPaise'] as int,
        minPriors: j['minPriors'] as int,
        lookbackDays: j['lookbackDays'] as int,
        duplicateWindowMinutes: j['duplicateWindowMinutes'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is AnomalyConfig &&
      other.outlierMultiple == outlierMultiple &&
      other.outlierMinPaise == outlierMinPaise &&
      other.minPriors == minPriors &&
      other.lookbackDays == lookbackDays &&
      other.duplicateWindowMinutes == duplicateWindowMinutes;

  @override
  int get hashCode => Object.hash(outlierMultiple, outlierMinPaise, minPriors,
      lookbackDays, duplicateWindowMinutes);
}

class RankerConfig {
  final int maxCards;
  final int maxPerType;

  /// Keyed by InsightKind.name. Integers: scores must stay exact.
  final Map<String, int> weights;
  const RankerConfig({
    required this.maxCards,
    required this.maxPerType,
    required this.weights,
  });

  factory RankerConfig.fromJson(Map<String, dynamic> j) => RankerConfig(
        maxCards: j['maxCards'] as int,
        maxPerType: j['maxPerType'] as int,
        weights: {
          for (final e in (j['weights'] as Map<String, dynamic>).entries)
            e.key: e.value as int
        },
      );

  @override
  bool operator ==(Object other) {
    if (other is! RankerConfig) return false;
    if (other.maxCards != maxCards || other.maxPerType != maxPerType) {
      return false;
    }
    if (other.weights.length != weights.length) return false;
    for (final e in weights.entries) {
      if (other.weights[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(maxCards, maxPerType, weights.length);
}

class InsightsConfig {
  final int version;
  final TrendConfig trend;
  final RecurrenceConfig recurrence;
  final AnomalyConfig anomaly;
  final RankerConfig ranker;
  const InsightsConfig({
    required this.version,
    required this.trend,
    required this.recurrence,
    required this.anomaly,
    required this.ranker,
  });

  factory InsightsConfig.fromJsonString(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    return InsightsConfig(
      version: j['version'] as int,
      trend: TrendConfig.fromJson(j['trend'] as Map<String, dynamic>),
      recurrence:
          RecurrenceConfig.fromJson(j['recurrence'] as Map<String, dynamic>),
      anomaly: AnomalyConfig.fromJson(j['anomaly'] as Map<String, dynamic>),
      ranker: RankerConfig.fromJson(j['ranker'] as Map<String, dynamic>),
    );
  }

  /// Mirrors the bundled JSON exactly; used only if the asset is missing.
  static const fallback = InsightsConfig(
    version: 1,
    trend: TrendConfig(
        minPct: 25, minAbsPaise: 50000, windowMonths: 3, concentrationPct: 70),
    recurrence: RecurrenceConfig(
        minOccurrences: 3,
        monthlyMinDays: 28,
        monthlyMaxDays: 33,
        weeklyMinDays: 6,
        weeklyMaxDays: 8,
        amountSpreadPct: 15,
        changedPct: 10,
        newWithinMonths: 2,
        activeWithinCadences: 2),
    anomaly: AnomalyConfig(
        outlierMultiple: 3,
        outlierMinPaise: 100000,
        minPriors: 5,
        lookbackDays: 35,
        duplicateWindowMinutes: 10),
    ranker: RankerConfig(maxCards: 5, maxPerType: 3, weights: {
      'possibleDuplicate': 4,
      'recurringNew': 3,
      'recurringChanged': 3,
      'outlierAmount': 2,
      'trend': 1,
      'committedSpend': 0,
    }),
  );

  @override
  bool operator ==(Object other) =>
      other is InsightsConfig &&
      other.version == version &&
      other.trend == trend &&
      other.recurrence == recurrence &&
      other.anomaly == anomaly &&
      other.ranker == ranker;

  @override
  int get hashCode => Object.hash(version, trend, recurrence, anomaly, ranker);
}
