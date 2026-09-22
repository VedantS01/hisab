import XCTest
@testable import HisabCore

final class RuleImpactTests: XCTestCase {

    // MARK: - an oracle that categorizes the way the app really does

    /// One transaction as the app stores it, before any category is derived.
    ///
    /// The point of carrying the raw ingredients rather than a hand-written
    /// `currentCategory` is that the "before" category comes out of
    /// `CategoryMatcher` rather than out of the test author's head — a fixture
    /// whose current category was asserted by hand could disagree with what the
    /// app would really show and the test would never notice.
    private struct Fixture {
        var text: String
        /// The user's explicit choice, if any.
        var override: String?
        /// Bank rows with no payment-app counterpart fall back to
        /// `Miscellaneous` rather than `Uncategorized` — see
        /// `Queries.effectiveCategory`.
        var isBankRow: Bool = false
    }

    /// A transcription of `Queries.effectiveCategory` minus self transfers
    /// (which are decided by reconciliation, never by a rule). `Queries` lives
    /// in the app target, which has no test target, so the semantics are
    /// mirrored here deliberately.
    ///
    /// Used only to build the "before" picture. The *expected counts* below are
    /// hand-computed literals, never derived from this helper: now that
    /// `affectedCount` simulates the matcher, re-deriving the answer from the
    /// matcher and comparing would assert nothing at all.
    private func effectiveCategory(_ fixture: Fixture, rules: [CategoryRule]) -> String {
        if let override = fixture.override { return override }
        let auto = CategoryMatcher(rules: rules).category(for: fixture.text)
        if auto == Categorizer.uncategorized && fixture.isBankRow {
            return Categorizer.miscellaneous
        }
        return auto
    }

    private func rows(_ fixtures: [Fixture], rules: [CategoryRule]) -> [RuleImpact.Row] {
        fixtures.map {
            RuleImpact.Row(text: $0.text,
                           hasOverride: $0.override != nil,
                           currentCategory: effectiveCategory($0, rules: rules))
        }
    }

    // MARK: - the point of fix round 1: the count is exact, not a lower bound

    /// THE test for this round. A row that a *shorter* existing pattern already
    /// claims — seed rule `ola` → Transport matching inside "COCA COLA" — used
    /// to read as already-categorized and go uncounted, while the longer
    /// proposed `coca cola` rule took it anyway. The count was a lower bound and
    /// rows changed silently. Simulating the matcher makes it 1.
    ///
    /// Seed rules like `ola`, `jio` and `uber` are three to four characters and
    /// occur inside ordinary merchant names, so this is reachable in the shipped
    /// ruleset, not a contrivance.
    func testCountsARowAShorterExistingPatternAlreadyClaims() {
        let existing = [CategoryRule(pattern: "ola", category: "Transport")]
        let proposed = CategoryRule(pattern: "coca cola", category: "Groceries")
        let fixture = Fixture(text: "UPI-COCA COLA INDIA PVT", override: nil)

        // The row reads as Transport today, because "ola" occurs inside "cola".
        XCTAssertEqual(effectiveCategory(fixture, rules: existing), "Transport")

        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows([fixture], rules: existing),
                                                rules: existing),
                       1,
                       "the longer proposed pattern takes the row from `ola`, so "
                       + "the user must be told it changes")
    }

    // MARK: - the cases the original brief asked about

    func testMiscellaneousRowsDoChangeSoCountingThemIsCorrect() {
        // B1's first suspicion was that Miscellaneous might be assigned by
        // reconciliation and outrank a new rule, which would make every
        // Miscellaneous row in the count a row that never changes. It does not:
        // Miscellaneous is the DISPLAY fallback for a bank row the matcher
        // returned Uncategorized for, so a matching rule replaces it outright.
        let fixture = Fixture(text: "POS ZOMATO LTD GURGAON", override: nil, isBankRow: true)
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")

        XCTAssertEqual(effectiveCategory(fixture, rules: []), Categorizer.miscellaneous)
        XCTAssertEqual(effectiveCategory(fixture, rules: [proposed]), "Food Delivery")
        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows([fixture], rules: []),
                                                rules: []),
                       1)
    }

    /// The flip side of the case above, and the one the simulation could get
    /// wrong: a bank row that matches NOTHING shows `Miscellaneous`, while the
    /// matcher returns `Uncategorized` for it. Comparing the raw matcher verdict
    /// against the displayed category would count every unmatched bank row in
    /// the store as "affected" by any rule at all.
    func testDoesNotCountAMiscellaneousBankRowTheRuleDoesNotMatch() {
        let fixture = Fixture(text: "ATM WDL 22SEP", override: nil, isBankRow: true)
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")

        XCTAssertEqual(effectiveCategory(fixture, rules: []), Categorizer.miscellaneous)
        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows([fixture], rules: []),
                                                rules: []),
                       0)
    }

    func testLongerCompetingPatternKeepsTheRowAndIsNotCounted() {
        // The matcher takes the longest pattern, so an existing longer rule
        // keeps the row and nothing changes.
        let existing = [CategoryRule(pattern: "zomato hyperpure", category: "Business Supplies")]
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")
        let fixture = Fixture(text: "UPI-ZOMATO HYPERPURE-XYZ", override: nil)

        XCTAssertEqual(effectiveCategory(fixture, rules: existing + [proposed]),
                       "Business Supplies")
        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows([fixture], rules: existing),
                                                rules: existing),
                       0)
    }

    /// The proposed rule is APPENDED, which matters only for a tie between
    /// patterns of equal length: `CategoryMatcher` breaks those on the lowest
    /// rule index, so the existing rule keeps the row. That is what the app
    /// really does — a rule accepted from an offer is stored at the end of the
    /// list — and prepending here would predict a change that never happens.
    func testAnEqualLengthExistingPatternWinsBecauseTheProposedRuleIsAppended() {
        let existing = [CategoryRule(pattern: "zomato", category: "Food Delivery")]
        let proposed = CategoryRule(pattern: "swiggy", category: "Groceries")
        // Carries both patterns, which are the same length (6).
        let fixture = Fixture(text: "UPI-ZOMATO-SWIGGY SETTLEMENT", override: nil)

        XCTAssertEqual(effectiveCategory(fixture, rules: existing), "Food Delivery")
        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows([fixture], rules: existing),
                                                rules: existing),
                       0,
                       "appended, so the existing equal-length rule keeps the tie")
    }

    func testCountsAnUncategorizedMatch() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", category: "Food Delivery",
                                                rows: rows, rules: []), 1)
    }

    func testExcludesARowTheUserCategorizedByHand() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: true,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", category: "Food Delivery",
                                                rows: rows, rules: []), 0,
                       "a rule must never override an explicit choice")
    }

    /// Replaces `testExcludesAnAlreadyCategorizedRow`, whose premise the exact
    /// count retires: an already-categorized row is now counted whenever the
    /// proposed rule outranks the rule holding it (see the `coca cola` test).
    /// What survives is the narrower true statement — a row the rule would leave
    /// showing the same category is not a change, so it is not counted.
    func testDoesNotCountARowAlreadyInTheCategoryTheRuleAssigns() {
        let existing = [CategoryRule(pattern: "upi-zomato", category: "Food Delivery")]
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: "Food Delivery")]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", category: "Food Delivery",
                                                rows: rows, rules: existing), 0,
                       "the row matches, but it already shows that category")
    }

    /// Self transfers are labeled by reconciliation ahead of any rule
    /// (`Queries.effectiveCategory` returns before it consults the matcher), so
    /// a rule can never move one. The old substring count excluded them by
    /// accident — they are neither Uncategorized nor Miscellaneous — and the
    /// simulation has to exclude them on purpose.
    func testExcludesASelfTransfer() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: Categorizer.selfTransfer)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", category: "Food Delivery",
                                                rows: rows, rules: []), 0)
    }

    func testEmptyPatternAffectsNothing() {
        // An empty needle is contained in every string; CategoryMatcher ignores
        // empty patterns outright, so "everything" would be doubly wrong.
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized),
                    RuleImpact.Row(text: "ANYTHING", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "", category: "Food Delivery",
                                                rows: rows, rules: []), 0)
    }

    func testMatchingIsCaseInsensitiveOnBothSides() {
        let rows = [RuleImpact.Row(text: "upi-ZoMaTo ltd", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "ZOMATO", category: "Food Delivery",
                                                rows: rows, rules: []), 1)
    }

    /// Several rows in one call, so the count is exercised as a count and not
    /// only as a one-row predicate — and so the matcher built once outside the
    /// loop is proven to serve every row.
    func testCountsAcrossAMixedSetOfRows() {
        let existing = [
            CategoryRule(pattern: "swiggy", category: "Food Delivery"),
            CategoryRule(pattern: "zomato hyperpure", category: "Business Supplies"),
            CategoryRule(pattern: "ola", category: "Transport"),
        ]
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")

        let fixtures = [
            // Uncategorized and matches: counted.
            Fixture(text: "UPI-ZOMATO LTD MUMBAI", override: nil),
            // Matches, but the user chose by hand: never touched.
            Fixture(text: "Zomato Gold membership", override: "Entertainment"),
            // Categorized by another rule and does not match anyway.
            Fixture(text: "SWIGGY INSTAMART", override: nil),
            // Miscellaneous bank row that matches: counted.
            Fixture(text: "POS ZOMATO LTD GURGAON", override: nil, isBankRow: true),
            // Matches the proposed pattern AND a longer existing one, which
            // wins: unchanged.
            Fixture(text: "UPI-ZOMATO HYPERPURE-XYZ", override: nil),
            // Miscellaneous but no match: unchanged.
            Fixture(text: "ATM WDL 22SEP", override: nil, isBankRow: true),
        ]

        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                category: proposed.category,
                                                rows: rows(fixtures, rules: existing),
                                                rules: existing),
                       2,
                       "the UPI row and the Miscellaneous bank row")
    }
}
