/// How many existing rows a proposed categorization rule would change.
/// Port of `HisabCore/Sources/HisabCore/Capture/RuleImpact.swift`.
library;

import '../categories.dart';

/// One transaction as the impact count sees it.
///
/// Swift twin: `RuleImpact.Row`. It deliberately carries NO current category
/// — `affectedCount` derives both the before and the after itself — and both
/// exclusions below are facts about the row carried as booleans, never
/// inferred from the label the row displays, which a user-authored rule could
/// legitimately produce.
class RuleImpactRow {
  /// The text the matcher sees for this row — for a transaction,
  /// `"$counterparty $narration"`.
  final String text;

  /// True when the user set this row's category by hand.
  final bool hasOverride;

  /// True when reconciliation paired this row with its own counterpart.
  /// Not "the row displays Self Transfer": `Queries.effectiveCategory`
  /// decides this ahead of both the override and the matcher, so it is a
  /// property of the row rather than a category it could be assigned.
  final bool isSelfTransfer;

  const RuleImpactRow({
    required this.text,
    required this.hasOverride,
    required this.isSelfTransfer,
  });
}

/// The number this produces is shown to the user as "this will also update N
/// past transactions", so it is a promise, not a hint. It is therefore
/// computed by **simulation, not approximation**, and by simulating *both*
/// sides: the row is run through the same [CategoryMatcher] the app
/// categorizes with, once over the current rules and once over the current
/// rules plus the proposed one, and counted when the two verdicts differ.
///
/// It is NOT a substring test over rows that are currently un-categorized,
/// which made it a lower bound: seed rule `ola` → Transport takes
/// "UPI-COCA COLA INDIA PVT", so the row is not un-categorized and went
/// uncounted, yet a proposed `coca cola` rule is longer and does take it.
///
/// Nor does it compare one verdict against a sentinel category. Skipping any
/// row whose simulated verdict is `Uncategorized` cannot tell "no rule
/// matched" from "a rule matched and its category IS Uncategorized", and
/// re-introduces the same undercount for a proposed rule assigning one of the
/// three reserved names — reachable today through the settings screen's
/// free-text category field. Comparing two verdicts is exact by construction:
/// a row matching nothing before and nothing after yields
/// `Uncategorized == Uncategorized` and is correctly not counted, which is
/// what that skip was only approximating.
class RuleImpact {
  /// Rows whose category would really change once [pattern] → [category] is
  /// added to [rules].
  ///
  /// [rules] is the user's current rule list — the same one that produces
  /// every row's category today. The proposed rule is **appended**, not
  /// prepended. Ordering reaches the answer only through [CategoryMatcher]'s
  /// tie-break, which is the lowest rule index among patterns of *equal
  /// length*, so the two differ on exactly one case: a proposed pattern the
  /// same length as an existing one that also occurs in the row. Appending
  /// makes the existing rule win that tie, which is what genuinely happens —
  /// a rule the user accepts from an offer is stored at the end of the list.
  /// Prepending would predict a change the app would not make.
  ///
  /// Rows the user categorized by hand are never counted, because a rule must
  /// never override an explicit choice. Self transfers are excluded for the
  /// same reason: `Queries.effectiveCategory` labels them from reconciliation
  /// *before* the override check and before the matcher, so no rule can move
  /// one.
  static int affectedCount({
    required String pattern,
    required String category,
    required List<RuleImpactRow> rows,
    required List<CategoryRule> rules,
  }) {
    if (pattern.isEmpty) return 0;
    // Two automata for all rows, not two per row: building is O(sum of
    // pattern lengths) and matching is O(text), so the pair is built once
    // outside the loop for the same reason the single one was.
    final before = CategoryMatcher(rules);
    final after = CategoryMatcher([
      ...rules,
      CategoryRule(
          id: _proposedRuleId, pattern: pattern, category: category),
    ]);

    var count = 0;
    for (final row in rows) {
      if (row.hasOverride || row.isSelfTransfer) continue;
      if (before.category(row.text) != after.category(row.text)) count++;
    }
    return count;
  }

  /// The simulated rule is never persisted, so its id only has to exist.
  /// Swift's `CategoryRule.init` defaults it to a fresh `UUID()`.
  static const String _proposedRuleId =
      '00000000-0000-4000-8000-000000000000';
}
