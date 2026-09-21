import XCTest
@testable import HisabCore

final class CategoriesTests: XCTestCase {
    private func rule(_ pattern: String, _ category: String) -> CategoryRule {
        CategoryRule(pattern: pattern, category: category)
    }

    func testCaseInsensitiveSubstring() {
        let rules = [CategoryRule(pattern: "swiggy", category: "Food Delivery")]
        XCTAssertEqual(Categorizer.category(for: "SWIGGY*ORDER 8123", rules: rules), "Food Delivery")
    }

    /// Was "first match wins". It now passes because "amazon pay" is *longer*
    /// than "amazon", not because it is listed first — so both orderings agree.
    func testLongerPatternWinsRegardlessOfOrder() {
        let payFirst = [rule("amazon pay", "Wallet"), rule("amazon", "Shopping")]
        let amazonFirst = [rule("amazon", "Shopping"), rule("amazon pay", "Wallet")]
        for rules in [payFirst, amazonFirst] {
            XCTAssertEqual(Categorizer.category(for: "AMAZON PAY RECHARGE", rules: rules), "Wallet")
            XCTAssertEqual(Categorizer.category(for: "AMAZON RETAIL", rules: rules), "Shopping")
        }
    }

    /// The regression that motivated longest-match: `jio` used to shadow `ajio`
    /// whenever it happened to be listed first.
    func testAjioBeatsJioInEitherOrder() {
        let ajioFirst = [rule("ajio", "Shopping"), rule("jio", "Recharges & Bills")]
        let jioFirst = [rule("jio", "Recharges & Bills"), rule("ajio", "Shopping")]
        for rules in [ajioFirst, jioFirst] {
            XCTAssertEqual(Categorizer.category(for: "UPI/AJIO RETAIL/8812", rules: rules), "Shopping")
            XCTAssertEqual(Categorizer.category(for: "JIO PREPAID RECHARGE", rules: rules),
                           "Recharges & Bills")
        }
    }

    func testEqualLengthTieGoesToTheLowerRuleIndex() {
        let rules = [rule("abcd", "First"), rule("wxyz", "Second")]
        XCTAssertEqual(Categorizer.category(for: "wxyz then abcd", rules: rules), "First")
        XCTAssertEqual(Categorizer.category(for: "abcd then wxyz", rules: rules), "First")
    }

    func testDuplicatePatternResolvesToTheLowerIndex() {
        let rules = [rule("ola", "Transport"), rule("ola", "Cabs")]
        XCTAssertEqual(Categorizer.category(for: "OLA CABS 7781", rules: rules), "Transport")
    }

    /// An empty pattern matches at every position; left in, it would swallow
    /// every text. It is dropped at build time instead.
    func testEmptyPatternIsIgnored() {
        let rules = [rule("", "Swallow All"), rule("swiggy", "Food Delivery")]
        XCTAssertEqual(Categorizer.category(for: "SWIGGY*ORDER", rules: rules), "Food Delivery")
        XCTAssertEqual(Categorizer.category(for: "nothing here", rules: rules),
                       Categorizer.uncategorized)
        XCTAssertEqual(Categorizer.category(for: "", rules: rules), Categorizer.uncategorized)
        XCTAssertEqual(Categorizer.category(for: "anything", rules: [rule("", "Swallow All")]),
                       Categorizer.uncategorized)
    }

    func testMatchesAtStartAtEndAndRejectsOverlongPatterns() {
        let rules = [rule("zepto", "Groceries"), rule("supermarket chain", "Groceries")]
        XCTAssertEqual(Categorizer.category(for: "zepto marketplace", rules: rules), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "upi payment to zepto", rules: rules), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "market", rules: rules), Categorizer.uncategorized)
    }

    /// A shorter pattern that is a suffix of a longer one must still be found
    /// when it is the only match — that is what the output links are for.
    func testShorterSuffixPatternStillMatchesOnItsOwn() {
        let rules = [rule("bigbasket", "Groceries"), rule("basket", "Shopping")]
        XCTAssertEqual(Categorizer.category(for: "gift basket co", rules: rules), "Shopping")
        XCTAssertEqual(Categorizer.category(for: "bigbasket daily", rules: rules), "Groceries")
    }

    // MARK: Unicode
    //
    // The automaton is indexed on UTF-16 code units in both cores — see the
    // CategoryMatcher doc comment. These cases must produce identical results
    // in the Dart port (packages/hisab_core/test/engines_test.dart).

    func testNonASCIIPatternsMatchAndDoNotCrash() {
        let rules = [rule("café", "Dining"), rule("स्विगी", "Food Delivery"),
                     rule("上海", "Travel")]
        XCTAssertEqual(Categorizer.category(for: "PAIEMENT CAFÉ CENTRAL", rules: rules), "Dining")
        XCTAssertEqual(Categorizer.category(for: "UPI/स्विगी/8812", rules: rules), "Food Delivery")
        XCTAssertEqual(Categorizer.category(for: "上海 HOTEL", rules: rules), "Travel")
        XCTAssertEqual(Categorizer.category(for: "cafe without an accent", rules: rules),
                       Categorizer.uncategorized)
    }

    /// Pins the indexing unit. "🍕🍕" is 4 UTF-16 code units but only 2 Swift
    /// `Character`s; "abc" is 3 of either. If this core counted Characters the
    /// ASCII rule would win here and Dart (which counts UTF-16 natively) would
    /// disagree. Asserting the emoji rule wins proves both index the same way.
    func testLongestIsMeasuredInUTF16CodeUnitsNotGraphemeClusters() {
        let rules = [rule("abc", "ASCII"), rule("🍕🍕", "Emoji")]
        XCTAssertEqual(Categorizer.category(for: "abc 🍕🍕", rules: rules), "Emoji")
    }

    /// Pins the cross-core case-mapping guarantee. Swift and Dart lowercase
    /// 1,112,064 code points identically except for 466, none of them ASCII or
    /// Latin-1 (see the CategoryMatcher doc comment). U+0130 is the interesting
    /// one — Swift lowercases it to `i` + U+0307, Dart to plain `i` — but as
    /// long as rule and narration spell it the same way, both cores agree, and
    /// that agreement is what this asserts.
    func testCaseInsensitivityHoldsAcrossCoresForASCIIAndLatin1() {
        // (pattern, text, expected) — escaped so the source encoding cannot
        // silently normalize a literal differently in the two repos.
        let cases: [(String, String, String)] = [
            ("CAF\u{00C9}", "paiement caf\u{00E9} central", "Hit"),
            ("caf\u{00E9}", "PAIEMENT CAF\u{00C9} CENTRAL", "Hit"),
            ("\u{00C5}NGSTR\u{00D6}M", "\u{00E5}ngstr\u{00F6}m labs", "Hit"),
            // ß has no uppercase in either core's simple mapping: no match.
            ("stra\u{00DF}e", "STRASSE", Categorizer.uncategorized),
            // U+0130 spelled the same way on both sides — the safe case.
            ("\u{0130}stanbul", "\u{0130}STANBUL KEBAB", "Hit"),
        ]
        for (pattern, text, expected) in cases {
            XCTAssertEqual(Categorizer.category(for: text, rules: [rule(pattern, "Hit")]),
                           expected, "pattern '\(pattern)' vs text '\(text)'")
        }
    }

    /// Normalization is explicitly *not* handled, identically in both cores:
    /// precomposed é (U+00E9) and decomposed e+U+0301 are different code-unit
    /// sequences and do not match each other.
    func testUnicodeNormalizationIsNotApplied() {
        let rules = [rule("caf\u{00E9}", "Dining")]
        XCTAssertEqual(Categorizer.category(for: "cafe\u{0301} central", rules: rules),
                       Categorizer.uncategorized)
        XCTAssertEqual(Categorizer.category(for: "caf\u{00E9} central", rules: rules), "Dining")
    }

    func testNoMatchIsUncategorized() {
        XCTAssertEqual(Categorizer.category(for: "LOCAL KIRANA", rules: []), Categorizer.uncategorized)
    }

    func testSeedRulesClassifyCommonMerchants() {
        XCTAssertEqual(Categorizer.category(for: "SWIGGY*ORDER 8123", rules: Categorizer.seedRules), "Food Delivery")
        XCTAssertEqual(Categorizer.category(for: "UPI/BLINKIT/99", rules: Categorizer.seedRules), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "IRCTC CF", rules: Categorizer.seedRules), "Transport")
        XCTAssertGreaterThanOrEqual(Categorizer.seedRules.count, 12)
    }

    func testMatcherIsReusableAcrossManyTexts() {
        let matcher = CategoryMatcher(rules: Categorizer.seedRules)
        XCTAssertEqual(matcher.category(for: "SWIGGY*ORDER 8123"), "Food Delivery")
        XCTAssertEqual(matcher.category(for: "UPI/BLINKIT/99"), "Groceries")
        XCTAssertEqual(matcher.category(for: "nothing at all"), Categorizer.uncategorized)
        XCTAssertEqual(matcher.category(for: "SWIGGY*ORDER 8123"), "Food Delivery")
    }
}
