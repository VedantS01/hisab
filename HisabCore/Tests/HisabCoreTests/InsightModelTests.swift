import XCTest
@testable import HisabCore

final class InsightModelTests: XCTestCase {
    // Pinned so the Dart twin asserts the identical digests — the same
    // discipline as the content-hash pin tests.
    func testInsightIDsArePinnedAcrossPlatforms() {
        XCTAssertEqual(InsightID.make("trend|Food Delivery|2026-08|40"), "a84b5c10538a32a7")
        XCTAssertEqual(InsightID.make("recurring-new|netflix|64900"), "47007c34745ef802")
        XCTAssertEqual(InsightID.make("outlier|txn-42"), "0230759323d235ce")
    }

    func testKindRawValuesAreTheWireNames() {
        XCTAssertEqual(InsightKind.allCases.map(\.rawValue),
                       ["trend", "recurringNew", "recurringChanged",
                        "committedSpend", "possibleDuplicate", "outlierAmount"])
    }

    func testISTDayStringResolvesInIndianStandardTime() {
        // 2026-08-03 19:00 UTC is already 2026-08-04 in IST (+05:30).
        let date = Date(timeIntervalSince1970: 1_785_783_600)
        XCTAssertEqual(ISTDay.string(date), "2026-08-04")
    }

    func testISTDaysBetweenCountsCalendarDays() {
        let a = Date(timeIntervalSince1970: 1_785_000_000)
        let b = a.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(ISTDay.daysBetween(a, b), 3)
        XCTAssertEqual(ISTDay.daysBetween(b, a), -3)
    }
}
