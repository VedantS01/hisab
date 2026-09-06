import XCTest
@testable import HisabCore

/// Analytics consume the app layer's pre-filtered "counted" rows: every payment-app
/// transaction plus unmatched bank rows; matched bank rows and self transfers are
/// excluded upstream, so the math here is a plain sum.
final class AnalyticsTests: XCTestCase {
    private let sep = YearMonth(year: 2026, month: 9)

    private func txn(_ month: YearMonth, _ amount: Int64, dir: Direction = .debit,
                     category: String = "Food Delivery", merchant: String = "Swiggy",
                     kind: SourceKind = .paymentApp) -> AnalyticsTxn {
        AnalyticsTxn(month: month, amountPaise: amount, direction: dir,
                     category: category, merchant: merchant, sourceKind: kind)
    }

    func testMonthStatsSumsAppAndMiscBankRows() {
        let txns = [
            txn(sep, 10000),                                             // app spend
            txn(sep, 5000, category: "Miscellaneous", kind: .bank),      // bank-only spend
            txn(sep, 700_000, dir: .credit, kind: .bank),                // bank-only income
        ]
        let stats = Analytics.monthStats(txns, month: sep)
        XCTAssertEqual(stats.spendPaise, 15000)
        XCTAssertEqual(stats.incomePaise, 700_000)
        XCTAssertEqual(stats.netPaise, 685_000)
    }

    func testEmptyMonthIsZero() {
        let stats = Analytics.monthStats([], month: sep)
        XCTAssertEqual(stats.spendPaise, 0)
        XCTAssertEqual(stats.incomePaise, 0)
    }

    func testTrendSpansZeroMonths() {
        let txns = [txn(sep, 10000), txn(sep.advanced(by: -5), 4000)]
        let trend = Analytics.trend(txns, endingAt: sep, count: 6)
        XCTAssertEqual(trend.count, 6)
        XCTAssertEqual(trend.first?.month, sep.advanced(by: -5))
        XCTAssertEqual(trend[1].spendPaise, 0)
        XCTAssertEqual(trend.last?.spendPaise, 10000)
    }

    func testCategoryBreakdownTopPlusOther() {
        let txns = [
            txn(sep, 50000, category: "A"), txn(sep, 40000, category: "B"),
            txn(sep, 30000, category: "C"), txn(sep, 20000, category: "D"),
            txn(sep, 1000, dir: .credit, category: "A"),  // credits excluded
        ]
        let breakdown = Analytics.categoryBreakdown(txns, month: sep, top: 2)
        XCTAssertEqual(breakdown.map(\.category), ["A", "B", "Other"])
        XCTAssertEqual(breakdown.last?.paise, 50000)
    }

    func testTopMerchants() {
        let txns = [
            txn(sep, 50000, merchant: "Swiggy"), txn(sep, 30000, merchant: "Swiggy"),
            txn(sep, 60000, merchant: "Amazon"),
        ]
        let merchants = Analytics.topMerchants(txns, month: sep, top: 5)
        XCTAssertEqual(merchants.map(\.merchant), ["Swiggy", "Amazon"])
        XCTAssertEqual(merchants.first?.paise, 80000)
    }
}
