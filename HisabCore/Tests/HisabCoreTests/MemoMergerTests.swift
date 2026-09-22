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

    private func dayTime(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    private func memo(_ amount: Int64, _ payee: String, _ vpa: String?,
                      _ date: String) -> PendingMemo {
        PendingMemo(amountPaise: amount, direction: .debit, payee: payee, vpa: vpa,
                    accountTail: nil, date: day(date), capturedAt: day(date))
    }

    private func memoAt(_ amount: Int64, _ payee: String, _ vpa: String?,
                        _ date: Date) -> PendingMemo {
        PendingMemo(amountPaise: amount, direction: .debit, payee: payee, vpa: vpa,
                    accountTail: nil, date: date, capturedAt: date)
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
        // Two identical-looking memos, one real row: pairing is global and
        // greedy by distance, so the closer-dated memo wins the candidate
        // and the farther one stays pending. (Per-memo oldest-first greedy
        // claiming could instead let an older memo steal a nearer memo's
        // exact-date row — see testDoesNotSwapTwoMemosBetweenTwoCandidates.)
        let a = memo(45_000, "ZEPTO", nil, "2026-09-20")
        let b = memo(45_000, "ZEPTO", nil, "2026-09-21")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-21"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        let merged = MemoMerger.merge(memos: [a, b], candidates: [candidate])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[b.captureHash], id,
                       "the closer-dated memo claims the candidate")
        XCTAssertNil(merged[a.captureHash], "the farther memo stays pending")
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

    // MARK: - Fix round 1 (D1-D4)

    func testDoesNotMergeAcrossFourDateLabelsWhenTimesOfDayDiffer() {
        // D1: dateComponents(from:to:) measures elapsed time and borrows
        // across midnight. 2026-09-22 23:55 -> 2026-09-26 00:05 is four
        // date-labels apart but only 3d10m of elapsed time, so a naive
        // elapsed-time diff reports 3 days and wrongly merges.
        let m = memoAt(45_000, "ZEPTO", nil, dayTime("2026-09-22 23:55"))
        let candidate = MemoMergeCandidate(id: UUID(), date: dayTime("2026-09-26 00:05"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty,
                     "four date-labels apart must not merge, regardless of elapsed time")
    }

    func testStillMergesThreeDateLabelsApartWhenTimesOfDayDiffer() {
        // The other half of D1: the fix must not over-tighten. Three
        // date-labels apart still merges even with differing times of day.
        let m = memoAt(45_000, "ZEPTO", nil, dayTime("2026-09-22 23:55"))
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: dayTime("2026-09-25 00:05"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testDoesNotMergeOnASingleInitialPayeeToken() {
        // D2: raw substring containment made "M S DHONI" -> first token "m"
        // match almost any narration. Whole-token matching must decline.
        let m = memo(45_000, "M S DHONI", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "UPI-AMAZON PAY-AMAZON@YBL-ICICI0000123")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testMergesASingleInitialPayeeOntoItsRealRow() {
        // The other half of D2: whole-token matching must not simply disable
        // short-token matching outright.
        let m = memo(45_000, "M S DHONI", nil, "2026-09-22")
        let id = UUID()
        let candidate = MemoMergeCandidate(id: id, date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "UPI-M S DHONI-HDFC-123456")
        XCTAssertEqual(MemoMerger.merge(memos: [m], candidates: [candidate]), [m.captureHash: id])
    }

    func testDoesNotMergeAVPAThatIsASubstringOfAnother() {
        // D3: "ram@okhdfc" is a literal substring of "sriram@okhdfc" but a
        // different person. Tokens must be a whole-token subset, not a
        // substring match. The payee is chosen so it doesn't independently
        // match the narration either.
        let m = memo(45_000, "RAM KUMAR", "ram@okhdfc", "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .debit,
                                           narration: "UPI-SRIRAM-SRIRAM@OKHDFC-HDFC-99")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testDoesNotSwapTwoMemosBetweenTwoCandidates() {
        // D4: per-memo oldest-first greedy claiming lets M1 (older) steal
        // M2's exact-date candidate, pushing M2 onto M1's farther candidate
        // -- both "merge" but with swapped notes. Global closest-pair-first
        // assignment must not swap them.
        let m1 = memo(45_000, "ZEPTO", nil, "2026-09-20")
        let m2 = memo(45_000, "ZEPTO", nil, "2026-09-21")
        let candidateA = UUID() // far from m1's own date, but m1's true row
        let candidateB = UUID() // exact match for m2
        let candidates = [
            MemoMergeCandidate(id: candidateA, date: day("2026-09-23"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
            MemoMergeCandidate(id: candidateB, date: day("2026-09-21"), amountPaise: 45_000,
                               direction: .debit, narration: "ZEPTO MARKETPLACE"),
        ]
        let merged = MemoMerger.merge(memos: [m1, m2], candidates: candidates)
        XCTAssertEqual(merged[m2.captureHash], candidateB, "m2 keeps its exact-date row")
        XCTAssertEqual(merged[m1.captureHash], candidateA, "m1 gets its own, farther row")
    }

    func testDoesNotMergeOnDirectionMismatch() {
        let m = memo(45_000, "ZEPTO", nil, "2026-09-22")
        let candidate = MemoMergeCandidate(id: UUID(), date: day("2026-09-22"),
                                           amountPaise: 45_000, direction: .credit,
                                           narration: "ZEPTO MARKETPLACE")
        XCTAssertTrue(MemoMerger.merge(memos: [m], candidates: [candidate]).isEmpty)
    }

    func testTokensKeepsCombiningMarksAttached() {
        // राम = र + ा (combining vowel sign, U+093E) + म: two extended
        // grapheme clusters ("रा", "म"), both letters, so they concatenate
        // into one token rather than splitting at the combining mark.
        XCTAssertEqual(MemoMerger.tokens(of: "राम KIRANA"), ["राम", "kirana"])
    }
}
