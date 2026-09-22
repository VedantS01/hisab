import XCTest
@testable import HisabCore

final class MemoMergerTests: XCTestCase {
    private func day(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    private func memo(_ amount: Int64, _ payee: String, _ vpa: String?,
                      _ date: String) -> PendingMemo {
        PendingMemo(amountPaise: amount, direction: .debit, payee: payee, vpa: vpa,
                    accountTail: nil, date: day(date), capturedAt: day(date))
    }

    func testMergesOnVPAPresentInNarration() {
        let m = memo(45_000, "VEDANT SABOO", "vedant@okaxis", "2026-09-22")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "UPI-VEDANT SABOO-VEDANT@OKAXIS-HDFC-123456")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testMergesWithinThreeDays() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-25"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testDoesNotMergeBeyondThreeDays() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-26"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testDoesNotMergeOnAmountMismatch() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_001, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testDoesNotMergeOnPayeeMismatch() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "SWIGGY INSTAMART")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testOneCandidateServesOnlyOneMemo() {
        // Two identical-looking memos, one real row: the second must stay pending
        // rather than both claiming the same transaction.
        let a = memo(45_000, "ZEPTO", nil, "2026-09-20")
        let b = memo(45_000, "ZEPTO", nil, "2026-09-21")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-21"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        let merged = MemoMerger.merge(memos: [a, b], candidates: [candidate])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[a.captureHash], id,
                       "memos are claimed oldest-first, deterministically")
        XCTAssertNil(merged[b.captureHash], "the second memo stays pending")
    }

    func testPicksNearestDateAmongCandidates() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let near = UUID(), far = UUID()
        let candidates = [
            MemoMergeCandidate(id: far, date: day("2026-09-25"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
            MemoMergeCandidate(id: near, date: day("2026-09-22"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
        ]
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: candidates), [m.captureHash: near])
    }
}
