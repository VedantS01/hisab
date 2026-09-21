import XCTest
@testable import HisabCore

final class TrendDetectorTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ category: String, _ merchant: String = "Shop") -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: category, merchant: merchant)
    }

    private let window: Set<YearMonth> = [YearMonth(year: 2026, month: 5),
                                          YearMonth(year: 2026, month: 6),
                                          YearMonth(year: 2026, month: 7),
                                          YearMonth(year: 2026, month: 8)]

    func testRiseAboveBothGatesIsReported() {
        // Baseline 1,000.00 per month for three months; August is 2,000.00.
        let records = [record("a", "2026-05-10", 100_000, "Food"),
                       record("b", "2026-06-10", 100_000, "Food"),
                       record("c", "2026-07-10", 100_000, "Food"),
                       record("d", "2026-08-10", 120_000, "Food"),
                       record("e", "2026-08-20", 80_000, "Food")]
        let (insights, concentration) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .trend)
        XCTAssertEqual(insights[0].headline, "Food: ₹2,000.00")
        XCTAssertEqual(insights[0].detail, "up 100% vs your 3-month average")
        XCTAssertEqual(insights[0].mute, .category("Food"))
        XCTAssertEqual(Set(insights[0].evidenceIDs), ["d", "e"])
        XCTAssertTrue(concentration.isEmpty)
    }

    func testDropsAreReportedToo() {
        let records = [record("a", "2026-05-10", 200_000, "Fuel"),
                       record("b", "2026-06-10", 200_000, "Fuel"),
                       record("c", "2026-07-10", 200_000, "Fuel"),
                       record("d", "2026-08-10", 100_000, "Fuel")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 100_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].detail, "down 50% vs your 3-month average")
    }

    func testSmallDeltaFailsTheRupeeGateEvenAtAHighPercentage() {
        // +200% but only ₹200 — below minAbsPaise.
        let records = [record("a", "2026-05-10", 10_000, "Snacks"),
                       record("b", "2026-06-10", 10_000, "Snacks"),
                       record("c", "2026-07-10", 10_000, "Snacks"),
                       record("d", "2026-08-10", 30_000, "Snacks")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 30_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testACategoryWithNoBaselineIsNotATrend() {
        let records = [record("d", "2026-08-10", 500_000, "Furniture")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 500_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testOneDominantPurchaseIsAnnotatedAndFlaggedForCollision() {
        let records = [record("a", "2026-05-10", 100_000, "Shopping"),
                       record("b", "2026-06-10", 100_000, "Shopping"),
                       record("c", "2026-07-10", 100_000, "Shopping"),
                       record("d", "2026-08-10", 50_000, "Shopping"),
                       record("e", "2026-08-11", 1_200_000, "Shopping", "Croma")]
        let (insights, concentration) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: window, monthDebitTotalPaise: 1_250_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].detail,
                       "up 1150% vs your 3-month average — driven by one ₹12,000.00 payment to Croma")
        XCTAssertEqual(concentration, ["e"])
    }

    func testNoCompleteBaselineMonthsProducesNothing() {
        let records = [record("d", "2026-08-10", 500_000, "Food")]
        let (insights, _) = TrendDetector.detect(
            records: records, month: YearMonth(year: 2026, month: 8),
            completeMonths: [YearMonth(year: 2026, month: 8)],
            monthDebitTotalPaise: 500_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }
}
