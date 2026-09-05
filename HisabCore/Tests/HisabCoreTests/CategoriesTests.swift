import XCTest
@testable import HisabCore

final class CategoriesTests: XCTestCase {
    func testCaseInsensitiveSubstring() {
        let rules = [CategoryRule(pattern: "swiggy", category: "Food Delivery")]
        XCTAssertEqual(Categorizer.category(for: "SWIGGY*ORDER 8123", rules: rules), "Food Delivery")
    }

    func testFirstMatchWins() {
        let rules = [
            CategoryRule(pattern: "amazon pay", category: "Wallet"),
            CategoryRule(pattern: "amazon", category: "Shopping"),
        ]
        XCTAssertEqual(Categorizer.category(for: "AMAZON PAY RECHARGE", rules: rules), "Wallet")
        XCTAssertEqual(Categorizer.category(for: "AMAZON RETAIL", rules: rules), "Shopping")
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
}
