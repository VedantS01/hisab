import XCTest
@testable import HisabCore

final class ReconciliationTests: XCTestCase {
    private func istDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        YearMonth.istCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func txn(id: UUID = UUID(), day: Int, amount: Int64, dir: Direction = .debit, ref: String? = nil) -> ReconTxn {
        ReconTxn(id: id, date: istDate(2026, 9, day), amountPaise: amount, direction: dir, reference: ref)
    }

    func testReferenceMatchWinsAcrossDates() {
        let a = txn(day: 1, amount: 5000, ref: "UPI123")
        let b = txn(day: 6, amount: 5000, ref: "UPI123")   // 5 days apart, still matches on ref
        let result = Reconciler.reconcile(app: [a], bank: [b])
        XCTAssertEqual(result.matches, [MatchPair(appID: a.id, bankID: b.id, tier: .reference)])
        XCTAssertTrue(result.appUnmatched.isEmpty)
        XCTAssertTrue(result.bankOnly.isEmpty)
    }

    func testAmountDateWindowMatch() {
        let a = txn(day: 10, amount: 25000)
        let b = txn(day: 11, amount: 25000, ref: "BANKREF")  // ref differs/absent on app side -> tier 2
        let result = Reconciler.reconcile(app: [a], bank: [b])
        XCTAssertEqual(result.matches, [MatchPair(appID: a.id, bankID: b.id, tier: .amountDate)])
    }

    func testOutsideWindowUnmatched() {
        let a = txn(day: 10, amount: 25000)
        let b = txn(day: 14, amount: 25000)
        let result = Reconciler.reconcile(app: [a], bank: [b])
        XCTAssertTrue(result.matches.isEmpty)
        XCTAssertEqual(result.appUnmatched, [a.id])
        XCTAssertEqual(result.bankOnly, [b.id])
    }

    func testBankTxnConsumedAtMostOnce() {
        let a1 = txn(day: 10, amount: 25000)
        let a2 = txn(day: 10, amount: 25000)
        let b = txn(day: 10, amount: 25000)
        let result = Reconciler.reconcile(app: [a1, a2], bank: [b])
        XCTAssertEqual(result.matches.count, 1)
        XCTAssertEqual(result.appUnmatched.count, 1)
        XCTAssertTrue(result.bankOnly.isEmpty)
    }

    func testClosestDateWins() {
        let a = txn(day: 10, amount: 25000)
        let far = txn(day: 12, amount: 25000)
        let near = txn(day: 10, amount: 25000)
        let result = Reconciler.reconcile(app: [a], bank: [far, near])
        XCTAssertEqual(result.matches, [MatchPair(appID: a.id, bankID: near.id, tier: .amountDate)])
        XCTAssertEqual(result.bankOnly, [far.id])
    }

    func testDirectionMustAgree() {
        let a = txn(day: 10, amount: 25000, dir: .debit)
        let b = txn(day: 10, amount: 25000, dir: .credit)
        let result = Reconciler.reconcile(app: [a], bank: [b])
        XCTAssertTrue(result.matches.isEmpty)
    }
}
