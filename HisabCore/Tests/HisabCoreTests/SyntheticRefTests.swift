import XCTest
@testable import HisabCore

final class SyntheticRefTests: XCTestCase {
    func testFormatMatchesLegacyRecipe() {
        let d = DateComponents(calendar: YearMonth.istCalendar, year: 2026, month: 4, day: 1).date!
        XCTAssertEqual(SyntheticRef.make(balancePaise: 90_000, date: d, amountPaise: 10_000),
                       "B90000D20260401A10000")
    }

    func testLegacyIDFCDelegateIsIdentical() {
        let d = DateComponents(calendar: YearMonth.istCalendar, year: 2026, month: 12, day: 31).date!
        XCTAssertEqual(IDFCStatementText.syntheticReference(balancePaise: -5, date: d, amountPaise: 7),
                       SyntheticRef.make(balancePaise: -5, date: d, amountPaise: 7))
    }
}
