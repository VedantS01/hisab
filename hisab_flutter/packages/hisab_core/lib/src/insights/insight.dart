/// Insight value types. Port of Insight.swift — field names, enum names and
/// the id recipe must stay identical; the pin tests enforce it.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain.dart';

enum InsightKind {
  trend,
  recurringNew,
  recurringChanged,
  committedSpend,
  possibleDuplicate,
  outlierAmount,
}

enum Cadence { monthly, weekly }

/// What a card's overflow "don't show this" action suppresses.
sealed class MuteTarget {
  const MuteTarget();
}

class MuteMerchant extends MuteTarget {
  final String merchantKey;
  const MuteMerchant(this.merchantKey);
  @override
  bool operator ==(Object other) =>
      other is MuteMerchant && other.merchantKey == merchantKey;
  @override
  int get hashCode => merchantKey.hashCode;
}

class MuteCategory extends MuteTarget {
  final String category;
  const MuteCategory(this.category);
  @override
  bool operator ==(Object other) =>
      other is MuteCategory && other.category == category;
  @override
  int get hashCode => category.hashCode;
}

class RecurringSeries {
  final String merchantKey;
  final String displayMerchant;
  final Cadence cadence;
  final int medianPaise;

  /// Weekly series are scaled by 52/12 so one number sums across cadences.
  final int monthlyEquivalentPaise;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int count;
  final List<String> transactionIDs;
  const RecurringSeries({
    required this.merchantKey,
    required this.displayMerchant,
    required this.cadence,
    required this.medianPaise,
    required this.monthlyEquivalentPaise,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.transactionIDs,
  });
}

/// One card. Copy is generated in core so both platforms render the same
/// sentence and the parity fixture can assert it.
class Insight {
  final String id;
  final InsightKind kind;
  final String headline;
  final String detail;

  /// Transaction ids the card is evidence for.
  final List<String> evidenceIDs;

  /// Populated for committedSpend only.
  final List<RecurringSeries> series;
  final int score;
  final MuteTarget? mute;
  const Insight({
    required this.id,
    required this.kind,
    required this.headline,
    required this.detail,
    required this.evidenceIDs,
    this.series = const [],
    required this.score,
    required this.mute,
  });
}

class InsightRecord {
  final String id;
  final DateTime date;
  final int amountPaise;
  final Direction direction;
  final String category;
  final String merchant;
  const InsightRecord({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.category,
    required this.merchant,
  });
}

class InsightsInput {
  final List<InsightRecord> records;
  final List<DatePeriod> documentPeriods;
  final DateTime now;
  const InsightsInput({
    required this.records,
    required this.documentPeriods,
    required this.now,
  });
}

class Suppressions {
  final Set<String> dismissedIDs;
  final Set<String> mutedMerchants;
  final Set<String> mutedCategories;
  const Suppressions({
    this.dismissedIDs = const {},
    this.mutedMerchants = const {},
    this.mutedCategories = const {},
  });
}

class InsightsResult {
  /// Ranked, capped, suppression-applied — exactly what the strip shows.
  final List<Insight> cards;

  /// Every id generated this pass before suppression; the app prunes its
  /// dismissed set to this.
  final Set<String> allIDs;
  const InsightsResult({required this.cards, required this.allIDs});
}

class InsightID {
  /// First 16 hex characters of SHA256 over the canonical string.
  static String make(String canonical) =>
      sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);
}
