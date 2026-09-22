/// The categories worth offering as one-tap answers on a notification.
/// Port of `HisabCore/Sources/HisabCore/Capture/CategoryRanker.swift`.
library;

import '../categories.dart';
import '../domain.dart';
import '../suggestion_engine.dart';

class CategoryRanker {
  static const int windowDays = 90;

  static const Set<String> _excluded = {
    Categorizer.uncategorized,
    Categorizer.miscellaneous,
    Categorizer.selfTransfer,
  };

  /// Distinct categories of the bundled seed ruleset, in the order their
  /// first rule is declared.
  ///
  /// Derived from the SHIPPED ruleset — `assets/rulesets/india-default.json`,
  /// which `tool/sync_assets.sh` keeps byte-identical with Swift's
  /// `Resources/rulesets/india-default.json` — and never from
  /// [Categorizer.seedRules], the compiled fallback. That fallback is a
  /// 23-rule subset with a different first-appearance order and no
  /// "Food & Dining" at all, while the user's rule table is really seeded
  /// from the JSON, so offering a category only the fallback contains would
  /// be offering a category nothing will ever auto-fill again.
  ///
  /// Swift reads its copy through `Bundle.module` inside the core package.
  /// `hisab_core` is pure Dart with no asset loader, so the loaded [Ruleset]
  /// is passed in instead — the app already holds one (`AppState.ruleset`,
  /// loaded from that same asset in `main.dart`). Deriving the list here from
  /// a Dart constant would let the two cores drift the moment the JSON is
  /// bumped, which is the whole point of taking it as data.
  ///
  /// Declaration order is the tie-break, not a claim about the user: for
  /// someone with no history any order is a guess, and what the fallback
  /// actually owes is that the buttons are non-empty and the same on every
  /// launch.
  static List<String> seedCategories(Ruleset ruleset) {
    final seen = <String>{};
    final result = <String>[];
    for (final rule in ruleset.rules) {
      if (_excluded.contains(rule.category)) continue;
      if (seen.add(rule.category)) result.add(rule.category);
    }
    return result;
  }

  /// Highest debit *count* over the trailing window. Count, not spend: the
  /// question is "what does this user usually buy", and one large payment
  /// should not outrank a habit. Excluded: the two non-answers and self
  /// transfers. Ties break alphabetically so the buttons are deterministic.
  ///
  /// When history yields fewer than [limit] categories the remainder is
  /// topped up from the seed ruleset. `records` comes from
  /// `Queries.suggestionRecords`, which draws ONLY from imported statements,
  /// so a user who relies on capture and has never imported would otherwise
  /// get a notification with nothing on it but "Later", permanently. The
  /// top-up never reorders or displaces a history-derived category; it only
  /// fills the empty slots after them.
  static List<String> topCategories({
    required List<SpendRecord> records,
    required DateTime now,
    required int limit,
    required Ruleset ruleset,
  }) {
    if (limit <= 0) return [];
    final windowStart =
        now.subtract(const Duration(days: windowDays));
    final counts = <String, int>{};
    for (final record in records) {
      if (record.direction != Direction.debit) continue;
      if (record.date.isBefore(windowStart)) continue;
      if (record.date.isAfter(now)) continue;
      if (_excluded.contains(record.effectiveCategory)) continue;
      counts[record.effectiveCategory] =
          (counts[record.effectiveCategory] ?? 0) + 1;
    }
    final ordered = counts.keys.toList()
      ..sort((a, b) => counts[a] == counts[b]
          ? a.compareTo(b)
          : counts[b]!.compareTo(counts[a]!));
    final chosen = ordered.take(limit).toList();

    if (chosen.length >= limit) return chosen;
    final have = chosen.toSet();
    for (final category in seedCategories(ruleset)) {
      if (chosen.length >= limit) break;
      if (have.add(category)) chosen.add(category);
    }
    return chosen;
  }
}
