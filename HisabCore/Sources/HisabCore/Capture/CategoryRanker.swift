import Foundation

/// The categories worth offering as one-tap answers on a notification.
public enum CategoryRanker {
    public static let windowDays = 90

    private static let excluded: Set<String> = [Categorizer.uncategorized,
                                                Categorizer.miscellaneous,
                                                Categorizer.selfTransfer]

    /// Distinct categories of the bundled seed ruleset, in the order their
    /// first rule is declared.
    ///
    /// CORRECTED (fix round 2, F3): this derived from `Categorizer.seedRules`,
    /// the 23-rule COMPILED FALLBACK whose own doc says it is used only if the
    /// resource is missing. The user's rule table is really seeded from
    /// `Categorizer.defaultRuleset()` — `Resources/rulesets/india-default.json`,
    /// which `Queries.categoryRules` inserts from — a superset with categories
    /// the compiled list lacks (Food & Dining, Travel, Investments, Insurance,
    /// Rent & Home, Education, Entertainment) and a different first-appearance
    /// order. Offering a category the user's own rule table does not contain
    /// would be offering a category nothing will ever auto-fill again.
    /// `defaultRuleset()` carries the fallback to `seedRules` internally, so
    /// this handles a missing resource exactly the way the seeding code does.
    ///
    /// Declaration order is the tie-break, not a claim about the user: for
    /// someone with no history any order is a guess, and what the fallback
    /// actually owes is that the buttons are non-empty and the same on every
    /// launch. First-appearance order gives that and keeps the everyday
    /// categories (food, groceries, transport) ahead of the occasional ones,
    /// which a count of seed patterns per category would not — over the shipped
    /// ruleset it would open with Shopping and Recharges & Bills and leave Food
    /// Delivery, which has only two patterns, last of fifteen.
    static let seedCategories: [String] = {
        var seen: Set<String> = []
        return Categorizer.defaultRuleset().rules.compactMap { rule in
            guard !excluded.contains(rule.category), seen.insert(rule.category).inserted
            else { return nil }
            return rule.category
        }
    }()

    /// Highest debit *count* over the trailing window. Count, not spend: the
    /// question is "what does this user usually buy", and one large payment
    /// should not outrank a habit. Excluded: the two non-answers and self
    /// transfers. Ties break alphabetically so the buttons are deterministic.
    ///
    /// When history yields fewer than `limit` categories the remainder is
    /// topped up from the seed ruleset. `records` comes from
    /// `Queries.suggestionRecords`, which draws ONLY from imported statements,
    /// so a user who relies on capture and has never imported would otherwise
    /// get a notification with nothing on it but "Later", permanently — and
    /// they are exactly the population whose statements lag. The top-up never
    /// reorders or displaces a history-derived category; it only fills the
    /// empty slots after them.
    public static func topCategories(records: [SpendRecord], now: Date,
                                     limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var counts: [String: Int] = [:]
        for record in records
        where record.direction == .debit
            && record.date >= windowStart
            && record.date <= now
            && !excluded.contains(record.effectiveCategory) {
            counts[record.effectiveCategory, default: 0] += 1
        }
        var chosen = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)

        guard chosen.count < limit else { return chosen }
        var have = Set(chosen)
        for category in seedCategories where chosen.count < limit {
            if have.insert(category).inserted { chosen.append(category) }
        }
        return chosen
    }
}
