import XCTest
@testable import HisabCore

final class YearMonthTests: XCTestCase {
    func testOrdering() {
        XCTAssertLessThan(YearMonth(year: 2025, month: 12), YearMonth(year: 2026, month: 1))
        XCTAssertLessThan(YearMonth(year: 2026, month: 1), YearMonth(year: 2026, month: 2))
    }

    func testAdvancedAcrossYearBoundary() {
        XCTAssertEqual(YearMonth(year: 2025, month: 12).advanced(by: 1), YearMonth(year: 2026, month: 1))
        XCTAssertEqual(YearMonth(year: 2026, month: 1).advanced(by: -1), YearMonth(year: 2025, month: 12))
        XCTAssertEqual(YearMonth(year: 2026, month: 3).advanced(by: -15), YearMonth(year: 2024, month: 12))
    }

    func testMonthsFromThroughInclusive() {
        let months = YearMonth.months(from: YearMonth(year: 2025, month: 4), through: YearMonth(year: 2026, month: 3))
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, YearMonth(year: 2025, month: 4))
        XCTAssertEqual(months.last, YearMonth(year: 2026, month: 3))
    }

    func testInitFromDateUsesIST() {
        // 2026-01-31 20:00 UTC == 2026-02-01 01:30 IST
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 20))!
        XCTAssertEqual(YearMonth(date: date), YearMonth(year: 2026, month: 2))
    }

    func testDescriptions() {
        let ym = YearMonth(year: 2026, month: 9)
        XCTAssertEqual(ym.description, "2026-09")
        XCTAssertEqual(ym.displayName, "Sep 2026")
    }
}
