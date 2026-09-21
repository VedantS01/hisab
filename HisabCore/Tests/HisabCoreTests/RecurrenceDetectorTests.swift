import XCTest
@testable import HisabCore

final class RecurrenceDetectorTests: XCTestCase {
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
                        _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: "Subscriptions", merchant: merchant)
    }

    private let now = "2026-09-15"

    func testMonthlySeriesIsDiscovered() {
        let records = [record("a", "2026-06-05", 64_900, "NETFLIX INDIA"),
                       record("b", "2026-07-05", 64_900, "Netflix India"),
                       record("c", "2026-08-05", 64_900, "NETFLIX INDIA"),
                       record("d", "2026-09-05", 64_900, "NETFLIX INDIA")]
        let series = RecurrenceDetector.series(records: records, now: day(now), config: config)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].merchantKey, "netflix india")
        XCTAssertEqual(series[0].displayMerchant, "NETFLIX INDIA")
        XCTAssertEqual(series[0].cadence, .monthly)
        XCTAssertEqual(series[0].medianPaise, 64_900)
        XCTAssertEqual(series[0].monthlyEquivalentPaise, 64_900)
        XCTAssertEqual(series[0].count, 4)
    }

    func testWeeklySeriesScalesToAMonthlyEquivalent() {
        let records = [record("a", "2026-08-25", 30_000, "Milk Wala"),
                       record("b", "2026-09-01", 30_000, "Milk Wala"),
                       record("c", "2026-09-08", 30_000, "Milk Wala"),
                       record("d", "2026-09-15", 30_000, "Milk Wala")]
        let series = RecurrenceDetector.series(records: records, now: day(now), config: config)
        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].cadence, .weekly)
        XCTAssertEqual(series[0].monthlyEquivalentPaise, 30_000 * 52 / 12)
    }

    func testIrregularGapsAreNotASeries() {
        let records = [record("a", "2026-06-01", 50_000, "Random Shop"),
                       record("b", "2026-06-19", 50_000, "Random Shop"),
                       record("c", "2026-08-02", 50_000, "Random Shop")]
        XCTAssertTrue(RecurrenceDetector.series(records: records, now: day(now),
                                                config: config).isEmpty)
    }

    func testTooFewOccurrencesIsNotASeries() {
        let records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix")]
        XCTAssertTrue(RecurrenceDetector.series(records: records, now: day(now),
                                                config: config).isEmpty)
    }

    func testAStaleSeriesIsNotActiveAndProducesNoCards() {
        // Last paid in March; monthly cadence goes inactive after 2 cadences.
        let records = [record("a", "2025-12-05", 64_900, "Netflix"),
                       record("b", "2026-01-05", 64_900, "Netflix"),
                       record("c", "2026-02-05", 64_900, "Netflix"),
                       record("d", "2026-03-05", 64_900, "Netflix")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 100_000, config: config)
        XCTAssertTrue(insights.isEmpty)
    }

    func testANewSeriesIsReported() {
        let records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix"),
                       record("c", "2026-09-05", 64_900, "Netflix")]
        let (insights, claimed) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .recurringNew)
        XCTAssertEqual(insights[0].headline, "New recurring: Netflix")
        XCTAssertEqual(insights[0].detail, "₹649.00 per month since Jul 2026")
        XCTAssertEqual(insights[0].mute, .merchant("netflix"))
        XCTAssertEqual(claimed, ["a", "b", "c"])
    }

    func testAChangedAmountIsReported() {
        // Established since February, so not "new"; September jumps 23%.
        let records = [record("a", "2026-02-05", 64_900, "Netflix"),
                       record("b", "2026-03-05", 64_900, "Netflix"),
                       record("c", "2026-04-05", 64_900, "Netflix"),
                       record("d", "2026-05-05", 64_900, "Netflix"),
                       record("e", "2026-06-05", 64_900, "Netflix"),
                       record("f", "2026-07-05", 64_900, "Netflix"),
                       record("g", "2026-08-05", 64_900, "Netflix"),
                       record("h", "2026-09-05", 79_900, "Netflix")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 200_000, config: config)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].kind, .recurringChanged)
        XCTAssertEqual(insights[0].headline, "Netflix: ₹799.00")
        XCTAssertEqual(insights[0].detail, "usually ₹649.00 per month")
    }

    func testTwoActiveSeriesProduceACommittedSpendSummary() {
        var records = [record("a", "2026-07-05", 64_900, "Netflix"),
                       record("b", "2026-08-05", 64_900, "Netflix"),
                       record("c", "2026-09-05", 64_900, "Netflix")]
        records += [record("d", "2026-07-10", 1_500_000, "Landlord"),
                    record("e", "2026-08-10", 1_500_000, "Landlord"),
                    record("f", "2026-09-10", 1_500_000, "Landlord")]
        let (insights, _) = RecurrenceDetector.detect(
            records: records, now: day(now), monthDebitTotalPaise: 2_000_000, config: config)
        let committed = insights.filter { $0.kind == .committedSpend }
        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed[0].headline, "₹15,649.00 per month committed")
        XCTAssertEqual(committed[0].detail, "across 2 recurring payments")
        XCTAssertEqual(committed[0].series.count, 2)
        XCTAssertNil(committed[0].mute)
    }
}
