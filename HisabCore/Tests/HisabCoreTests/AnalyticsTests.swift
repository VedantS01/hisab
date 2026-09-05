import XCTest
@testable import HisabCore

final class AnalyticsTests: XCTestCase {
    private let sep = YearMonth(year: 2026, month: 9)
    private let aug = YearMonth(year: 2026, month: 8)

    private func txn(_ month: YearMonth, _ amount: Int64, dir: Direction = .debit,
                     category: String = "Food Delivery", merchant: String = "Swiggy",
                     kind: SourceKind = .bank) -> AnalyticsTxn {
        AnalyticsTxn(month: month, amountPaise: amount, direction: dir,
                     category: category, merchant: merchant, sourceKind: kind)
    }

    func testBankBasisIgnoresAppTxns() {
        let txns = [txn(sep, 10000, kind: .bank), txn(sep, 99999, kind: .paymentApp)]
        let stats = Analytics.monthStats(txns, month: sep)
        XCTAssertEqual(stats.spendPaise, 10000)
        XCTAssertEqual(stats.basis, .bank)
    }

    func testPaymentAppFallback() {
        let txns = [txn(sep, 5000, kind: .paymentApp), txn(sep, 7000, dir: .credit, kind: .paymentApp)]
        let stats = Analytics.monthStats(txns, month: sep)
        XCTAssertEqual(stats.spendPaise, 5000)
        XCTAssertEqual(stats.incomePaise, 7000)
        XCTAssertEqual(stats.netPaise, 2000)
        XCTAssertEqual(stats.basis, .paymentApps)
    }

    func testEmptyMonthIsZeroNone() {
        let stats = Analytics.monthStats([], month: sep)
        XCTAssertEqual(stats.spendPaise, 0)
        XCTAssertEqual(stats.basis, Basis.none)
    }

    func testTrendSpansZeroMonths() {
        let txns = [txn(sep, 10000), txn(sep.advanced(by: -5), 4000)]
        let trend = Analytics.trend(txns, endingAt: sep, count: 6)
        XCTAssertEqual(trend.count, 6)
        XCTAssertEqual(trend.first?.month, sep.advanced(by: -5))
        XCTAssertEqual(trend.last?.month, sep)
        XCTAssertEqual(trend[1].spendPaise, 0)
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
