import XCTest
@testable import HisabCore

final class RulesetTests: XCTestCase {
    func testDefaultRulesetLoadsAndIsSubstantial() {
        let ruleset = Categorizer.defaultRuleset()
        XCTAssertGreaterThanOrEqual(ruleset.version, 1)
        XCTAssertGreaterThanOrEqual(ruleset.rules.count, 55)
    }

    func testEveryCompiledSeedPatternSurvivesInTheRuleset() {
        let patterns = Set(Categorizer.defaultRuleset().rules.map { $0.pattern.lowercased() })
        for seed in Categorizer.seedRules {
            XCTAssertTrue(patterns.contains(seed.pattern.lowercased()),
                          "compiled seed '\(seed.pattern)' missing from india-default")
        }
    }

    func testNoDuplicatePatternsAndNoEmptyCategories() {
        let rules = Categorizer.defaultRuleset().rules
        let patterns = rules.map { $0.pattern.lowercased() }
        XCTAssertEqual(Set(patterns).count, patterns.count, "duplicate patterns")
        for rule in rules {
            XCTAssertFalse(rule.category.isEmpty)
            XCTAssertFalse(rule.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func testRulesetDrivesCategorization() {
        let rules = Categorizer.defaultRuleset().rules.map {
            CategoryRule(pattern: $0.pattern, category: $0.category)
        }
        XCTAssertEqual(Categorizer.category(for: "ZERODHA BROKING LTD", rules: rules), "Investments")
        XCTAssertEqual(Categorizer.category(for: "UPI/DR/1/BLINKIT", rules: rules), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "totally unknown merchant", rules: rules),
                       Categorizer.uncategorized)
    }

    /// `jio` is a substring of both `jiomart` and `ajio` — the only overlapping
    /// patterns in the bundled ruleset. Longest-match resolves all three without
    /// the list order mattering, so the file stays pure data.
    func testOverlappingBundledPatternsResolveByLength() {
        let rules = Categorizer.defaultRuleset().rules.map {
            CategoryRule(pattern: $0.pattern, category: $0.category)
        }
        XCTAssertEqual(Categorizer.category(for: "UPI/AJIO RETAIL/8812", rules: rules), "Shopping")
        XCTAssertEqual(Categorizer.category(for: "JIOMART GROCERY ORDER", rules: rules), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "JIO PREPAID RECHARGE", rules: rules),
                       "Recharges & Bills")

        // Shuffled input must give the same answers: order is no longer meaningful.
        let reversed = Array(rules.reversed())
        XCTAssertEqual(Categorizer.category(for: "UPI/AJIO RETAIL/8812", rules: reversed), "Shopping")
        XCTAssertEqual(Categorizer.category(for: "JIOMART GROCERY ORDER", rules: reversed), "Groceries")
        XCTAssertEqual(Categorizer.category(for: "JIO PREPAID RECHARGE", rules: reversed),
                       "Recharges & Bills")
    }

    /// Every bundled pattern must still classify to its own category when it is
    /// the only merchant token in the text — a guard against a future rule
    /// addition silently shadowing an existing one.
    func testEveryBundledPatternStillClassifiesToItsOwnCategory() {
        let seeds = Categorizer.defaultRuleset().rules
        let rules = seeds.map { CategoryRule(pattern: $0.pattern, category: $0.category) }
        let matcher = CategoryMatcher(rules: rules)
        for seed in seeds {
            let resolved = matcher.category(for: "UPI/\(seed.pattern.uppercased())/8812")
            XCTAssertEqual(resolved, seed.category,
                           "'\(seed.pattern)' resolved to \(resolved), expected \(seed.category)")
        }
    }
}
