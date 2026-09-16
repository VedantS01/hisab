import XCTest
@testable import HisabCore

final class SuggestionEngineTests: XCTestCase {
    private let now = DateComponents(calendar: YearMonth.istCalendar,
                                     year: 2026, month: 9, day: 15, hour: 12).date!

    private func record(_ merchant: String, rupees: Int64, daysAgo: Int,
                        direction: Direction = .debit,
                        category: String = Categorizer.uncategorized) -> SpendRecord {
        SpendRecord(merchant: merchant, amountPaise: rupees * 100,
                    date: now.addingTimeInterval(TimeInterval(-daysAgo) * 86_400),
                    direction: direction, effectiveCategory: category)
    }

    /// Background spend so the 2%-of-window gate has a denominator.
    private var background: [SpendRecord] {
        (0..<10).map { record("MISC MERCHANT \($0)", rupees: 2_000, daysAgo: 10 + $0,
                              category: "Shopping") }
    }

    func testQualifyingClusterSurfacesWithTotals() {
        let records = background + [
            record("BLUE TOKAI 4213", rupees: 700, daysAgo: 5),
            record("BLUE TOKAI 8821", rupees: 800, daysAgo: 20),
            record("BLUE TOKAI 1100", rupees: 900, daysAgo: 45),
        ]
        let queue = SuggestionEngine.queue(records: records, now: now, muted: [])
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue[0].merchantPattern, "blue tokai")
        XCTAssertEqual(queue[0].totalPaise, 240_000)
        XCTAssertEqual(queue[0].count, 3)
    }

    func testBelowFloorTotalIsExcluded() {
        let records = background + [
            record("TINY CHAI", rupees: 100, daysAgo: 5),
            record("TINY CHAI", rupees: 100, daysAgo: 35),
            record("TINY CHAI", rupees: 100, daysAgo: 65),
        ]
        XCTAssertTrue(SuggestionEngine.queue(records: records, now: now, muted: []).isEmpty)
    }

    func testSingleMonthFrequencyIsExcluded() {
        let records = background + [
            record("ONE MONTH SHOP", rupees: 900, daysAgo: 2),
            record("ONE MONTH SHOP", rupees: 900, daysAgo: 3),
            record("ONE MONTH SHOP", rupees: 900, daysAgo: 4),
        ]
        XCTAssertTrue(SuggestionEngine.queue(records: records, now: now, muted: []).isEmpty)
    }

    func testMutedMerchantNeverReturns() {
        let records = background + [
            record("BLUE TOKAI", rupees: 700, daysAgo: 5),
            record("BLUE TOKAI", rupees: 800, daysAgo: 40),
            record("BLUE TOKAI", rupees: 900, daysAgo: 70),
        ]
        XCTAssertTrue(SuggestionEngine.queue(records: records, now: now,
                                             muted: ["blue tokai"]).isEmpty)
    }

    func testCreditsAndCategorizedAndStaleRecordsNeverCount() {
        let records = background + [
            record("SALARY CO", rupees: 90_000, daysAgo: 5, direction: .credit),
            record("SALARY CO", rupees: 90_000, daysAgo: 40, direction: .credit),
            record("SALARY CO", rupees: 90_000, daysAgo: 70, direction: .credit),
            record("KNOWN SHOP", rupees: 5_000, daysAgo: 5, category: "Shopping"),
            record("KNOWN SHOP", rupees: 5_000, daysAgo: 40, category: "Shopping"),
            record("KNOWN SHOP", rupees: 5_000, daysAgo: 70, category: "Shopping"),
            record("OLD HAUNT", rupees: 5_000, daysAgo: 100),
            record("OLD HAUNT", rupees: 5_000, daysAgo: 120),
            record("OLD HAUNT", rupees: 5_000, daysAgo: 140),
        ]
        XCTAssertTrue(SuggestionEngine.queue(records: records, now: now, muted: []).isEmpty)
    }

    func testOrderedBySpendImpact() {
        let records = background + [
            record("SMALLER SPEND", rupees: 600, daysAgo: 5),
            record("SMALLER SPEND", rupees: 600, daysAgo: 40),
            record("SMALLER SPEND", rupees: 600, daysAgo: 70),
            record("BIGGER SPEND", rupees: 3_000, daysAgo: 6),
            record("BIGGER SPEND", rupees: 3_000, daysAgo: 41),
            record("BIGGER SPEND", rupees: 3_000, daysAgo: 71),
        ]
        let queue = SuggestionEngine.queue(records: records, now: now, muted: [])
        XCTAssertEqual(queue.map(\.merchantPattern), ["bigger spend", "smaller spend"])
    }

    func testNormalizeStripsDigitsPunctuationAndTruncates() {
        XCTAssertEqual(SuggestionEngine.normalize("BLUE TOKAI COFFEE 4213 BLR"),
                       "blue tokai coffee")
        XCTAssertEqual(SuggestionEngine.normalize("UPI/DR/12345/CHAI-POINT"),
                       "upi dr chai")
        XCTAssertEqual(SuggestionEngine.normalize("  ACME  "), "acme")
    }
}
