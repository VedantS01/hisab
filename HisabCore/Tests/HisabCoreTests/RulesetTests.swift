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
}
