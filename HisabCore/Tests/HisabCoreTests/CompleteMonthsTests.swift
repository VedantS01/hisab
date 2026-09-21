import XCTest
@testable import HisabCore

final class CompleteMonthsTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    func testAMonthIsCompleteOnlyWhenOnePeriodSpansItEntirely() {
        // Apr 1 – Jun 30, both at IST midnight: April and May are covered
        // end to end, but June's last instant is 2026-06-30T23:59:59 IST —
        // past where the period ends — so June is not complete.
        let period = DatePeriod(start: date("2026-04-01"), end: date("2026-06-30"))
        let months = CompleteMonths.of([period])
        XCTAssertEqual(months, [YearMonth(year: 2026, month: 4),
                                YearMonth(year: 2026, month: 5)])
    }

    func testPartialEdgeMonthsAreExcluded() {
        // The statement starts mid-April and stops mid-June: only May is whole.
        let period = DatePeriod(start: date("2026-04-15"), end: date("2026-06-14"))
        XCTAssertEqual(CompleteMonths.of([period]), [YearMonth(year: 2026, month: 5)])
    }

    func testLatestIgnoresMonthsAfterNow() {
        // Jan 1 – Dec 31, both at IST midnight: January–November are
        // complete (December fails for the same reason June did above).
        // notAfter caps at September, which is itself complete, so that's
        // the answer.
        let period = DatePeriod(start: date("2026-01-01"), end: date("2026-12-31"))
        let latest = CompleteMonths.latest([period], notAfter: date("2026-09-10"))
        XCTAssertEqual(latest, YearMonth(year: 2026, month: 9))
    }

    func testNoPeriodsMeansNoCompleteMonths() {
        XCTAssertTrue(CompleteMonths.of([]).isEmpty)
        XCTAssertNil(CompleteMonths.latest([], notAfter: date("2026-09-10")))
    }
}
