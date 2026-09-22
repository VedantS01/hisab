import Foundation

/// How many existing rows a proposed categorization rule would change.
///
/// The number this produces is shown to the user as "this will also update N
/// past transactions", so it is a promise, not a hint. It is therefore computed
/// by **simulation, not approximation**: the count runs the row through the
/// same `CategoryMatcher` the app categorizes with, once with the proposed rule
/// added, and compares the answer to what the row shows today.
///
/// It used to be a substring test over rows that were currently un-categorized,
/// which made it a lower bound. That test disagreed with the matcher on a row
/// some *shorter* existing pattern already claimed — seed rule `ola` → Transport
/// takes "UPI-COCA COLA INDIA PVT", so the row is not un-categorized and went
/// uncounted, yet a proposed `coca cola` rule is longer and does take it. Rows
/// changed while the user was told nothing. Running the matcher removes that
/// divergence and any other of its kind, because there is no longer a second
/// definition of "matches" to drift from the first.
///
/// **Rows the user categorized by hand are never counted**, because a rule must
/// never override an explicit choice — `Queries.category(of:rules:)` returns
/// `categoryOverride` before it consults any rule. Self transfers are excluded
/// for the same reason: `Queries.effectiveCategory` labels them from
/// reconciliation before any rule is consulted, so no rule can move one.
public enum RuleImpact {
    public struct Row: Sendable {
        /// The text the matcher sees for this row — for a transaction,
        /// `"\(counterparty) \(narration)"`.
        public var text: String
        /// True when the user set this row's category by hand.
        public var hasOverride: Bool
        /// The category the row shows today, override and the bank-row
        /// `Miscellaneous` fallback included.
        public var currentCategory: String

        public init(text: String, hasOverride: Bool, currentCategory: String) {
            self.text = text
            self.hasOverride = hasOverride
            self.currentCategory = currentCategory
        }
    }

    /// Rows whose category would really change once `pattern` → `category` is
    /// added to `rules`.
    ///
    /// `rules` is the user's current rule list — the same one that produced
    /// every row's `currentCategory`. The proposed rule is **appended**, not
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
        // One automaton for all rows: building is O(sum of pattern lengths) and
        // matching is O(text), so a matcher per row would cost more than the
        // whole simulation does.
        let matcher = CategoryMatcher(rules: rules
            + [CategoryRule(pattern: pattern, category: category)])

        return rows.filter { row in
            guard !row.hasOverride else { return false }
            guard row.currentCategory != Categorizer.selfTransfer else { return false }
            let simulated = matcher.category(for: row.text)
            // `Uncategorized` means no pattern matched at all — and since adding
            // a rule can only ever ADD matches, a row nothing matches now is a
            // row nothing matched before. Its displayed category is whatever the
            // no-match fallback gives it (`Uncategorized`, or `Miscellaneous`
            // for a bank row), and comparing a raw matcher verdict against that
            // fallback would count every un-matched bank row as changed.
            guard simulated != Categorizer.uncategorized else { return false }
            return simulated != row.currentCategory
        }.count
    }
}
