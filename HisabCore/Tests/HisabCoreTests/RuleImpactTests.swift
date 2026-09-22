import XCTest
@testable import HisabCore

final class RuleImpactTests: XCTestCase {

    // MARK: - an oracle that categorizes the way the app really does

    /// One transaction as the app stores it, before any category is derived.
    ///
    /// The point of carrying the raw ingredients rather than a hand-written
    /// `currentCategory` is that the "before" and "after" categories both come
    /// out of `CategoryMatcher`. A test that hand-wrote the current category
    /// could only ever confirm the arithmetic it was given.
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
    /// (which are decided by reconciliation, never by a rule, and so can never
    /// be affected by one). `Queries` lives in the app target, which has no
    /// test target, so the semantics are mirrored here deliberately.
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

    /// How many rows genuinely change category once `proposed` is appended to
    /// the rule list — the ground truth `affectedCount` is claiming to predict.
    private func actualChangeCount(_ fixtures: [Fixture], rules: [CategoryRule],
                                   proposed: CategoryRule) -> Int {
        fixtures.filter {
            effectiveCategory($0, rules: rules) != effectiveCategory($0, rules: rules + [proposed])
        }.count
    }

    // MARK: - B1: the count must agree with how the app actually categorizes

    func testAffectedCountAgreesWithCategoryMatcher() {
        // Ordering matters to the matcher only as a tie-break; these three are
        // the world the proposed rule lands in.
        let existing = [
            CategoryRule(pattern: "swiggy", category: "Food Delivery"),
            // Longer than the proposed pattern, and overlapping it: this is the
            // competitor that would beat "zomato" on a row carrying both.
            CategoryRule(pattern: "zomato hyperpure", category: "Business Supplies"),
            CategoryRule(pattern: "ola", category: "Transport"),
        ]
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")

        let fixtures = [
            // Uncategorized, matches: must be counted and must change.
            Fixture(text: "UPI-ZOMATO LTD MUMBAI", override: nil),
            // Matches, but the user chose by hand: a rule must not touch it.
            Fixture(text: "Zomato Gold membership", override: "Entertainment"),
            // Already categorized by another rule, and does not match anyway.
            Fixture(text: "SWIGGY INSTAMART", override: nil),
            // Miscellaneous (bank row the matcher could not place) and matches:
            // the question B1 poses about Miscellaneous precedence.
            Fixture(text: "POS ZOMATO LTD GURGAON", override: nil, isBankRow: true),
            // Matches the proposed pattern AND a longer existing one, which
            // wins: counted nowhere, changes nothing.
            Fixture(text: "UPI-ZOMATO HYPERPURE-XYZ", override: nil),
            // Miscellaneous but no match: neither counted nor changed.
            Fixture(text: "ATM WDL 22SEP", override: nil, isBankRow: true),
        ]

        let predicted = RuleImpact.affectedCount(pattern: proposed.pattern,
                                                 rows: rows(fixtures, rules: existing))
        let actual = actualChangeCount(fixtures, rules: existing, proposed: proposed)

        // Pinned literally as well as compared, so two coincidentally-equal
        // zeroes could never pass this.
        XCTAssertEqual(predicted, 2, "the UPI row and the Miscellaneous bank row")
        XCTAssertEqual(actual, 2)
        XCTAssertEqual(predicted, actual,
                       "affectedCount is a promise to the user; it must equal what "
                       + "CategoryMatcher really does once the rule is added")
    }

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
                                                rows: rows([fixture], rules: [])), 1)
    }

    func testLongerCompetingPatternKeepsTheRowAndIsNotCounted() {
        // The second suspicion, and it holds up: the matcher takes the longest
        // pattern, so an existing longer rule keeps the row — and because that
        // rule already gave the row a real category, affectedCount excludes it.
        // Agreement here is not luck; it is the same fact seen twice.
        let existing = [CategoryRule(pattern: "zomato hyperpure", category: "Business Supplies")]
        let proposed = CategoryRule(pattern: "zomato", category: "Food Delivery")
        let fixture = Fixture(text: "UPI-ZOMATO HYPERPURE-XYZ", override: nil)

        XCTAssertEqual(effectiveCategory(fixture, rules: existing + [proposed]),
                       "Business Supplies")
        XCTAssertEqual(RuleImpact.affectedCount(pattern: proposed.pattern,
                                                rows: rows([fixture], rules: existing)), 0)
    }

    /// FINDING (task 11a): the one case where the two genuinely disagree.
    ///
    /// A row that a *shorter* existing pattern already categorizes is not
    /// `Uncategorized`, so `affectedCount` skips it — but the proposed pattern
    /// is longer, so the matcher hands the row to the new rule anyway. The
    /// count is therefore a LOWER BOUND: rows can change silently, never the
    /// other way round. Seed rules like `ola`, `jio` and `uber` are three to
    /// four characters long and occur inside ordinary merchant names, so this
    /// is reachable in the shipped ruleset, not a contrivance.
    ///
    /// This test records the real semantics. It does NOT bless them: fixing it
    /// means giving `affectedCount` the current rule list and running the
    /// matcher per row, which changes the signature Task 14's Dart port
    /// mirrors, so it is the controller's call, not this task's.
    func testCountUndercountsWhenTheProposedPatternOutranksAShorterOne() {
        let existing = [CategoryRule(pattern: "ola", category: "Transport")]
        let proposed = CategoryRule(pattern: "coca cola", category: "Groceries")
        let fixture = Fixture(text: "UPI-COCA COLA INDIA PVT", override: nil)

        // Today the row reads as Transport, because "ola" occurs inside "cola".
        XCTAssertEqual(effectiveCategory(fixture, rules: existing), "Transport")
        // Adding the longer rule really does move it.
        XCTAssertEqual(effectiveCategory(fixture, rules: existing + [proposed]), "Groceries")

        let predicted = RuleImpact.affectedCount(pattern: proposed.pattern,
                                                 rows: rows([fixture], rules: existing))
        let actual = actualChangeCount([fixture], rules: existing, proposed: proposed)
        XCTAssertEqual(predicted, 0, "excluded: the row is not Uncategorized today")
        XCTAssertEqual(actual, 1, "but it changes anyway — the count is a lower bound")
        XCTAssertNotEqual(predicted, actual,
                          "if this ever becomes equal, affectedCount was made exact "
                          + "and this test should be replaced by an agreement assertion")
    }

    // MARK: - the four cases the original brief asked for

    func testCountsAnUncategorizedMatch() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", rows: rows), 1)
    }

    func testExcludesARowTheUserCategorizedByHand() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: true,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", rows: rows), 0,
                       "a rule must never override an explicit choice")
    }

    func testExcludesAnAlreadyCategorizedRow() {
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: "Food Delivery")]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "zomato", rows: rows), 0)
    }

    func testEmptyPatternAffectsNothing() {
        // An empty needle is contained in every string; CategoryMatcher ignores
        // empty patterns outright, so "everything" would be doubly wrong.
        let rows = [RuleImpact.Row(text: "UPI-ZOMATO LTD", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized),
                    RuleImpact.Row(text: "ANYTHING", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "", rows: rows), 0)
    }

    func testMatchingIsCaseInsensitiveOnBothSides() {
        let rows = [RuleImpact.Row(text: "upi-ZoMaTo ltd", hasOverride: false,
                                   currentCategory: Categorizer.uncategorized)]
        XCTAssertEqual(RuleImpact.affectedCount(pattern: "ZOMATO", rows: rows), 1)
    }
}
