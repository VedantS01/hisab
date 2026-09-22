import XCTest
@testable import HisabCore

/// One schema, two languages: pins `AlertParser.parse` and `MemoMerger.merge`
/// so the two cores cannot silently disagree on either. Unit tests on each
/// side prove a core matches its own expectations; this fixture is the only
/// artifact that proves the two cores match *each other*.
///
/// Set ALERT_GT_OUT to a *directory* to regenerate `captureHash` values (in
/// `cases` and `merges[].memos`) and the `merges[].expected` maps from the
/// current Swift implementation (same env-gated dump pattern as
/// InsightsParityTests / SamplesGroundTruthDump). Every other field is
/// authored by hand and MUST NOT change on a dump — if it does, that is a
/// parser bug, not a fixture to update.
final class AlertParityTests: XCTestCase {
    private struct Fixture: Codable {
        struct CaseExpected: Codable, Equatable {
            var amountPaise: Int64
            var direction: String
            var payee: String
            var payeeNormalized: String
            var vpa: String?
            var accountTail: String?
            var dateISO: String
            var captureHash: String
            var rulePattern: String
            var ruleKind: String
        }
        struct Case: Codable {
            var name: String
            var text: String
            var expected: CaseExpected
        }
        struct MergeMemo: Codable {
            var id: String
            var amountPaise: Int64
            var direction: String
            var payee: String
            var vpa: String?
            var accountTail: String?
            var dateISO: String
            var captureHash: String
        }
        struct MergeCandidate: Codable {
            var id: String
            var dateISO: String
            var amountPaise: Int64
            var direction: String
            var narration: String
        }
        struct MergeCase: Codable {
            var name: String
            var memos: [MergeMemo]
            var candidates: [MergeCandidate]
            var expected: [String: String]
        }

        var receivedAt: String
        var cases: [Case]
        var rejected: [String]
        var merges: [MergeCase]
    }

    private func parseISO(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso) else {
            fatalError("bad ISO8601 date in fixture: \(iso)")
        }
        return date
    }

    /// Midnight-ish (noon, matching AlertParser.makeDate's convention) IST
    /// instant for a `yyyy-MM-dd` day string.
    private func dayDate(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        precondition(parts.count == 3, "bad yyyy-MM-dd: \(iso)")
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let date = YearMonth.istCalendar.date(from: components) else {
            fatalError("could not build date from \(iso)")
        }
        return date
    }

    private func direction(_ raw: String) -> Direction {
        guard let direction = Direction(rawValue: raw) else {
            fatalError("bad direction in fixture: \(raw)")
        }
        return direction
    }

    func testAlertParserAndMemoMergerAgreeWithDart() throws {
        let dumpDir = ProcessInfo.processInfo.environment["ALERT_GT_OUT"]

        let url = try XCTUnwrap(Bundle.module.url(forResource: "alert-parity",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"),
                                "missing fixture alert-parity.json")
        var fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let receivedAt = parseISO(fixture.receivedAt)

        // MARK: cases
        for (index, testCase) in fixture.cases.enumerated() {
            guard let memo = AlertParser.parse(text: testCase.text, receivedAt: receivedAt) else {
                XCTFail("\(testCase.name): expected a parse, got nil")
                continue
            }
            let actual = Fixture.CaseExpected(
                amountPaise: memo.amountPaise,
                direction: memo.direction.rawValue,
                payee: memo.payee,
                payeeNormalized: memo.payeeNormalized,
                vpa: memo.vpa,
                accountTail: memo.accountTail,
                dateISO: PendingMemo.istDayString(memo.date),
                captureHash: memo.captureHash,
                rulePattern: memo.ruleKey.pattern,
                ruleKind: memo.ruleKey.kind.rawValue)

            if dumpDir != nil {
                fixture.cases[index].expected = actual
                continue
            }
            XCTAssertEqual(actual, testCase.expected, "\(testCase.name): parse result differs")
        }

        // MARK: rejected
        for text in fixture.rejected {
            XCTAssertNil(AlertParser.parse(text: text, receivedAt: receivedAt),
                         "expected nil for rejected text: \(text)")
        }

        // MARK: merges
        for (mergeIndex, mergeCase) in fixture.merges.enumerated() {
            let memos = mergeCase.memos.map { m -> PendingMemo in
                PendingMemo(amountPaise: m.amountPaise, direction: direction(m.direction),
                           payee: m.payee, vpa: m.vpa, accountTail: m.accountTail,
                           date: dayDate(m.dateISO), capturedAt: dayDate(m.dateISO))
            }
            let candidates = mergeCase.candidates.map { c -> MemoMergeCandidate in
                guard let id = UUID(uuidString: c.id) else {
                    fatalError("bad UUID in fixture: \(c.id)")
                }
                return MemoMergeCandidate(id: id, date: dayDate(c.dateISO),
                                          amountPaise: c.amountPaise,
                                          direction: direction(c.direction),
                                          narration: c.narration)
            }
            let result = MemoMerger.merge(memos: memos, candidates: candidates)
            let actualExpected = Dictionary(uniqueKeysWithValues:
                result.map { ($0.key, $0.value.uuidString.lowercased()) })

            if dumpDir != nil {
                for (memoIndex, memo) in memos.enumerated() {
                    fixture.merges[mergeIndex].memos[memoIndex].captureHash = memo.captureHash
                }
                fixture.merges[mergeIndex].expected = actualExpected
                continue
            }

            // Every memo's fixture-recorded hash must match what this run
            // computes -- catches drift in PendingMemo's hash algorithm
            // independent of the merge assignment itself.
            for (memoIndex, memo) in memos.enumerated() {
                XCTAssertEqual(memo.captureHash, mergeCase.memos[memoIndex].captureHash,
                               "\(mergeCase.name): memo \(mergeCase.memos[memoIndex].id) hash differs")
            }
            XCTAssertEqual(actualExpected, mergeCase.expected,
                           "\(mergeCase.name): merge assignment differs")
        }

        if let dumpDir {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(fixture)
            data.append(0x0A)  // keep the committed blob newline-terminated
            let out = URL(fileURLWithPath: dumpDir).appendingPathComponent("alert-parity.json")
            try data.write(to: out)
            print("alert-parity: wrote \(fixture.cases.count) cases, "
                 + "\(fixture.merges.count) merge scenarios to \(out.path)")
        }
    }
}
