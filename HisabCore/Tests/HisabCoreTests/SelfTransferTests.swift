import XCTest
@testable import HisabCore

final class SelfTransferTests: XCTestCase {
    private func istDate(_ d: Int) -> Date {
        YearMonth.istCalendar.date(from: DateComponents(year: 2026, month: 9, day: d, hour: 12))!
    }

    private func txn(id: UUID = UUID(), day: Int, amount: Int64, dir: Direction) -> ReconTxn {
        ReconTxn(id: id, date: istDate(day), amountPaise: amount, direction: dir, reference: nil)
    }

    func testCrossBankPairFlagged() {
        let out = txn(day: 10, amount: 2_000_000, dir: .debit)
        let inn = txn(day: 10, amount: 2_000_000, dir: .credit)
        let flagged = SelfTransfers.detect(bank: [(out, .hdfc), (inn, .idfc)])
        XCTAssertEqual(flagged, [out.id, inn.id])
    }

    func testSameBankPairNotFlagged() {
        let out = txn(day: 10, amount: 2_000_000, dir: .debit)
        let inn = txn(day: 10, amount: 2_000_000, dir: .credit)
        XCTAssertTrue(SelfTransfers.detect(bank: [(out, .hdfc), (inn, .hdfc)]).isEmpty)
    }

    func testAmountMismatchNotFlagged() {
        let out = txn(day: 10, amount: 2_000_000, dir: .debit)
        let inn = txn(day: 10, amount: 1_999_900, dir: .credit)
        XCTAssertTrue(SelfTransfers.detect(bank: [(out, .hdfc), (inn, .idfc)]).isEmpty)
    }

    func testOutsideWindowNotFlagged() {
        let out = txn(day: 1, amount: 2_000_000, dir: .debit)
        let inn = txn(day: 8, amount: 2_000_000, dir: .credit)
        XCTAssertTrue(SelfTransfers.detect(bank: [(out, .hdfc), (inn, .idfc)]).isEmpty)
    }

    func testCreditConsumedOnce() {
        let out1 = txn(day: 10, amount: 500_000, dir: .debit)
        let out2 = txn(day: 10, amount: 500_000, dir: .debit)
        let inn = txn(day: 10, amount: 500_000, dir: .credit)
        let flagged = SelfTransfers.detect(bank: [(out1, .hdfc), (out2, .hdfc), (inn, .idfc)])
        XCTAssertEqual(flagged.count, 2)
        XCTAssertTrue(flagged.contains(inn.id))
    }
}
