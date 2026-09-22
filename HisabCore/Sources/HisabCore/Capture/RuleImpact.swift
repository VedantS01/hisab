import Foundation

/// How many existing rows a proposed categorization rule would change.
///
/// The number this produces is shown to the user as "this will also update N
/// past transactions", so it is a promise, not a hint. It is therefore computed
/// by **simulation, not approximation**, and — since fix round 2 — by
/// simulating *both* sides: the row is run through the same `CategoryMatcher`
/// the app categorizes with, once over the current rules and once over the
/// current rules plus the proposed one, and counted when the two verdicts
/// differ.
///
/// It used to be a substring test over rows that were currently un-categorized,
/// which made it a lower bound. That test disagreed with the matcher on a row
/// some *shorter* existing pattern already claimed — seed rule `ola` → Transport
/// takes "UPI-COCA COLA INDIA PVT", so the row is not un-categorized and went
/// uncounted, yet a proposed `coca cola` rule is longer and does take it. Rows
/// changed while the user was told nothing.
///
/// Comparing two verdicts is exact **by construction**, and that is the point:
/// there is no sentinel to interpret and no display string to match. The first
/// attempt at the fix compared one verdict against the category the row
/// displays and skipped rows whose verdict was `Uncategorized`, which
/// re-introduced the very same undercount for a proposed rule whose category
/// happens to be one of the reserved names — reachable today through
/// `SettingsView`'s free-text category field. A row that matches nothing before
/// and nothing after now yields `Uncategorized == Uncategorized` and is
/// correctly not counted, which is what that skip was approximating.
///
/// **Rows the user categorized by hand are never counted**, because a rule must
/// never override an explicit choice — `Queries.effectiveCategory` returns
/// `categoryOverride` before it consults any rule. Self transfers are excluded
/// for the same reason: the same function labels them from reconciliation
/// *before* the override check and before the matcher, so no rule can move one.
/// Both exclusions are therefore facts about the row, carried as booleans — not
/// inferred from the label the row displays, which a user-authored rule could
/// legitimately produce.
public enum RuleImpact {
    public struct Row: Sendable {
        /// The text the matcher sees for this row — for a transaction,
        /// `"\(counterparty) \(narration)"`.
        public var text: String
        /// True when the user set this row's category by hand.
        public var hasOverride: Bool
        /// True when reconciliation paired this row with its own counterpart.
        /// Not "the row displays Self Transfer": `Queries.effectiveCategory`
        /// decides this ahead of both the override and the matcher, so it is a
        /// property of the row rather than a category it could be assigned.
        public var isSelfTransfer: Bool

        public init(text: String, hasOverride: Bool, isSelfTransfer: Bool) {
            self.text = text
            self.hasOverride = hasOverride
            self.isSelfTransfer = isSelfTransfer
        }
    }

    /// Rows whose category would really change once `pattern` → `category` is
    /// added to `rules`.
    ///
    /// `rules` is the user's current rule list — the same one that produces
    /// every row's category today. The proposed rule is **appended**, not
    /// prepended. Ordering reaches the answer only through `CategoryMatcher`'s
    /// tie-break, which is the lowest rule index among patterns of *equal
    /// length*, so the two differ on exactly one case: a proposed pattern the
    /// same length as an existing one that also occurs in the row. Appending
    /// makes the existing rule win that tie, which is what genuinely happens —
    /// a rule the user accepts from an offer is stored at the end of the list
    /// (`Queries.categoryRules` sorts by `sortOrder`, and a new rule takes the
    /// highest). Prepending would predict a change the app would not make.
    public static func affectedCount(pattern: String, category: String,
                                     rows: [Row], rules: [CategoryRule]) -> Int {
        guard !pattern.isEmpty else { return 0 }
        // Two automata for all rows, not two per row: building is O(sum of
        // pattern lengths) and matching is O(text), so the pair is built once
        // outside the loop for the same reason the single one was.
        let before = CategoryMatcher(rules: rules)
        let after = CategoryMatcher(rules: rules
            + [CategoryRule(pattern: pattern, category: category)])

        return rows.filter { row in
            guard !row.hasOverride, !row.isSelfTransfer else { return false }
            return before.category(for: row.text) != after.category(for: row.text)
        }.count
    }
}
