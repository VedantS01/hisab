import Foundation

/// How many existing rows a proposed categorization rule would change.
///
/// The number this produces is shown to the user as "this will also update N
/// past transactions", so it is a promise, not a hint. Two things follow.
///
/// **It is a lower bound, not the exact figure.** The app categorizes through
/// `CategoryMatcher` (Aho–Corasick, longest pattern wins, ties to the lowest
/// rule index); this counts with a plain substring test over rows that are
/// currently un-categorized. The two agree on every row that is currently
/// `Uncategorized` or `Miscellaneous` — see `RuleImpactTests` — because a row
/// only holds one of those when NO existing rule matches it, which leaves the
/// proposed rule the sole match and therefore the winner regardless of length.
/// They part company on a row that some *shorter* existing pattern already
/// categorizes: `ola` → Transport claims "coca cola india", so the row is not
/// un-categorized and is not counted here, yet a proposed `coca cola` rule is
/// longer and WOULD take it. Such rows change without being counted. Counting
/// them needs the caller's current rule list and a matcher run per row; this
/// signature deliberately does not take one, so the shortfall is recorded here
/// rather than hidden.
///
/// **Rows the user categorized by hand are never counted**, because a rule must
/// never override an explicit choice — `Queries.category(of:rules:)` returns
/// `categoryOverride` before it consults any rule.
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

    /// Rows a new `pattern` would newly categorize.
    ///
    /// `Miscellaneous` counts alongside `Uncategorized`: it is not a rule's
    /// output but the display fallback `Queries.effectiveCategory` applies to a
    /// bank row the matcher could not categorize, so a matching rule wins over
    /// it and the row really does change.
    public static func affectedCount(pattern: String, rows: [Row]) -> Int {
        let needle = pattern.lowercased()
        guard !needle.isEmpty else { return 0 }
        return rows.filter {
            !$0.hasOverride
                && $0.text.lowercased().contains(needle)
                && ($0.currentCategory == Categorizer.uncategorized
                    || $0.currentCategory == Categorizer.miscellaneous)
        }.count
    }
}
