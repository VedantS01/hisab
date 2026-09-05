import XCTest
@testable import HisabCore

final class DedupTests: XCTestCase {
    private func istDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        YearMonth.istCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func txn(ref: String?, amount: Int64 = 10000, narration: String = "row") -> ParsedTransaction {
        ParsedTransaction(date: istDate(2026, 9, 1), amountPaise: amount, direction: .debit,
                          counterparty: "X", reference: ref, narration: narration)
    }

    func testFiltersRowsAlreadyStored() {
        let existing = txn(ref: "A")
        let hashes: Set<String> = [existing.contentHash(source: .hdfc)]
        let incoming = [txn(ref: "A"), txn(ref: "B")]
        XCTAssertEqual(Dedup.newIndices(incoming: incoming, source: .hdfc, existingHashes: hashes), [1])
    }

    func testIntraBatchDuplicateKeepsFirst() {
        let incoming = [txn(ref: "A"), txn(ref: "A"), txn(ref: "B")]
        XCTAssertEqual(Dedup.newIndices(incoming: incoming, source: .hdfc, existingHashes: []), [0, 2])
    }

    func testDifferentReferencesBothKept() {
        let incoming = [txn(ref: "A"), txn(ref: "B")]
        XCTAssertEqual(Dedup.newIndices(incoming: incoming, source: .hdfc, existingHashes: []), [0, 1])
    }

    func testSameRowDifferentSourceNotConfused() {
        let stored = txn(ref: nil, narration: "same row")
        let hashes: Set<String> = [stored.contentHash(source: .gpay)]
        let incoming = [txn(ref: nil, narration: "same row")]
        XCTAssertEqual(Dedup.newIndices(incoming: incoming, source: .hdfc, existingHashes: hashes), [0])
    }
}
