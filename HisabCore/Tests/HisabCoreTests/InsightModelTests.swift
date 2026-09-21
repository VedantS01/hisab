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

        // IST has no DST, so an exact day-multiple offset can't distinguish
        // calendar-day truncation from a naive elapsed-seconds/86400 divide.
        // These pin actual IST wall-clock instants to rule that out.
        // 2026-08-03 23:00 IST -> 2026-08-04 01:00 IST: 2 hours elapsed, but
        // it crosses an IST midnight, so it must count as 1 day.
        let crossMidnightBefore = Date(timeIntervalSince1970: 1_785_778_200)
        let crossMidnightAfter = Date(timeIntervalSince1970: 1_785_785_400)
        XCTAssertEqual(ISTDay.daysBetween(crossMidnightBefore, crossMidnightAfter), 1)
        XCTAssertEqual(ISTDay.daysBetween(crossMidnightAfter, crossMidnightBefore), -1)

        // 2026-08-04 00:30 IST -> 2026-08-04 23:30 IST: 23 hours elapsed but
        // stays inside one IST calendar day, so it must count as 0 days.
        let sameDayEarly = Date(timeIntervalSince1970: 1_785_783_600)
        let sameDayLate = Date(timeIntervalSince1970: 1_785_866_400)
        XCTAssertEqual(ISTDay.daysBetween(sameDayEarly, sameDayLate), 0)
    }
}
