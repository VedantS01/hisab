import XCTest
@testable import HisabCore

final class DomainTests: XCTestCase {
    private func istDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        YearMonth.istCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testYearPeriodCoversTwelveMonths() {
        let period = DatePeriod(start: istDate(2025, 4, 1), end: istDate(2026, 3, 31))
        XCTAssertEqual(period.months.count, 12)
        XCTAssertEqual(period.months.first, YearMonth(year: 2025, month: 4))
        XCTAssertEqual(period.months.last, YearMonth(year: 2026, month: 3))
    }

    func testSingleDayPeriod() {
        let period = DatePeriod(start: istDate(2026, 9, 5), end: istDate(2026, 9, 5))
        XCTAssertEqual(period.months, [YearMonth(year: 2026, month: 9)])
    }

    func testSourceKinds() {
        XCTAssertEqual(Source.gpay.kind, .paymentApp)
        XCTAssertEqual(Source.paytm.kind, .paymentApp)
        XCTAssertEqual(Source.hdfc.kind, .bank)
        XCTAssertEqual(Source.idfc.kind, .bank)
    }

    private func txn(ref: String?, narration: String = "UPI/PAY/123/SWIGGY") -> ParsedTransaction {
        ParsedTransaction(date: istDate(2026, 9, 1), amountPaise: 25000, direction: .debit,
                          counterparty: "Swiggy", reference: ref, narration: narration)
    }

    func testHashStableAndSensitiveToReference() {
        XCTAssertEqual(txn(ref: "R1").contentHash(source: .gpay), txn(ref: "R1").contentHash(source: .gpay))
        XCTAssertNotEqual(txn(ref: "R1").contentHash(source: .gpay), txn(ref: "R2").contentHash(source: .gpay))
        XCTAssertNotEqual(txn(ref: "R1").contentHash(source: .gpay), txn(ref: "R1").contentHash(source: .paytm))
    }

    func testReferenceIsTheIdentityWithinASource() {
        // Same ref = same transaction, even when other fields drift between formats.
        let a = ParsedTransaction(date: istDate(2026, 9, 1), amountPaise: 25000, direction: .debit,
                                  counterparty: "Swiggy", reference: "R1", narration: "n1")
        let b = ParsedTransaction(date: istDate(2026, 9, 2), amountPaise: 25000, direction: .debit,
                                  counterparty: "SWIGGY LTD", reference: "R1", narration: "n2")
        XCTAssertEqual(a.contentHash(source: .gpay), b.contentHash(source: .gpay))
    }

    func testRefundKeepsItsOwnIdentity() {
        // Same reference, opposite direction (a cancellation) must NOT collide.
        let paid = ParsedTransaction(date: istDate(2026, 5, 23), amountPaise: 9455, direction: .debit,
                                     counterparty: "DigitalOcean", reference: "614317804525", narration: "POS")
        let refund = ParsedTransaction(date: istDate(2026, 5, 23), amountPaise: 9455, direction: .credit,
                                       counterparty: "DigitalOcean", reference: "614317804525", narration: "POS-CANCELLED")
        XCTAssertNotEqual(paid.contentHash(source: .idfc), refund.contentHash(source: .idfc))
    }

    func testHashFallsBackToNormalizedNarration() {
        let a = txn(ref: nil, narration: "UPI/PAY/123/SWIGGY  BANGALORE")
        let b = txn(ref: nil, narration: "  upi/pay/123/swiggy bangalore ")
        XCTAssertEqual(a.contentHash(source: .hdfc), b.contentHash(source: .hdfc))
        let c = txn(ref: nil, narration: "UPI/PAY/999/SWIGGY BANGALORE")
        XCTAssertNotEqual(a.contentHash(source: .hdfc), c.contentHash(source: .hdfc))
    }
}
