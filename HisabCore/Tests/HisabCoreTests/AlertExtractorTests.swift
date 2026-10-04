import XCTest
@testable import HisabCore

/// Pins the Swift extractor to the Python reference (`ml/src/hisab_ml`) through
/// the fixtures `hisab_ml.fixtures` writes. Every comparison is exact; each test
/// reports the first few mismatching cases.
final class AlertExtractorTests: XCTestCase {
    private static let maxReported = 5

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json",
                                                  subdirectory: "Fixtures"),
                                "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    private func report(_ mismatches: [String], of total: Int, _ what: String) {
        for line in mismatches.prefix(Self.maxReported) { XCTFail(line) }
        XCTAssertEqual(mismatches.count, 0, "\(what): \(mismatches.count) of \(total) cases differ")
    }

    // MARK: tokenizer

    private struct TokenizerFixture: Decodable {
        struct Case: Decodable {
            var text: String
            var ids: [Int32]
            var offsets: [[Int]]
        }
        var max_len: Int
        var cases: [Case]
    }

    func testTokenizerMatchesReference() throws {
        let fixture = try JSONDecoder().decode(TokenizerFixture.self, from: fixture("extractor-tokenizer"))
        let tokenizer = try AlertExtractor.Resources.bundled.get().tokenizer
        var mismatches: [String] = []
        for (index, testCase) in fixture.cases.enumerated() {
            let encoding = tokenizer.encode(tokenizer.prepare(Array(testCase.text.unicodeScalars)),
                                            maxLen: fixture.max_len)
            let offsets = encoding.offsets.map { [$0.start, $0.end] }
            guard encoding.ids != testCase.ids || offsets != testCase.offsets else { continue }
            let at = zip(encoding.ids, testCase.ids).enumerated().first { $1.0 != $1.1 }?.offset
                ?? zip(offsets, testCase.offsets).enumerated().first { $1.0 != $1.1 }?.offset
                ?? min(encoding.ids.count, testCase.ids.count)
            mismatches.append("""
                case \(index) \(testCase.text.debugDescription.prefix(80)): first difference at token \(at) \
                of \(testCase.ids.count) (got \(encoding.ids.count) tokens); \
                got \(Array(encoding.ids.dropFirst(at).prefix(4))) \(Array(offsets.dropFirst(at).prefix(4))), \
                want \(Array(testCase.ids.dropFirst(at).prefix(4))) \(Array(testCase.offsets.dropFirst(at).prefix(4)))
                """)
        }
        report(mismatches, of: fixture.cases.count, "tokenizer")
        XCTAssertGreaterThan(fixture.cases.count, 0)
    }

    // MARK: normalizers

    func testNormalizersMatchReference() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("extractor-normalize")) as? [String: Any])
        func pairs(_ key: String) throws -> [[Any]] { try XCTUnwrap(json[key] as? [[Any]], key) }
        func string(_ value: Any) -> String? { value as? String }
        func int(_ value: Any) -> Int64? { value is NSNull ? nil : (value as? NSNumber)?.int64Value }

        var mismatches: [String] = []
        var total = 0
        func check<T: Equatable>(_ name: String, _ rows: [[Any]], _ want: (Any) -> T?, _ fn: (String) -> T?) {
            for row in rows {
                total += 1
                let input = row[0] as! String
                let got = fn(input), expected = want(row[1])
                if got != expected {
                    mismatches.append("\(name)(\(input.debugDescription)): got \(String(describing: got)), " +
                                      "want \(String(describing: expected))")
                }
            }
        }
        check("amount_paise", try pairs("amount_paise"), int, ExtractorNormalize.amountPaise)
        check("ref", try pairs("ref"), string, ExtractorNormalize.ref)
        check("acct_tail", try pairs("acct_tail"), string, ExtractorNormalize.acctTail)
        check("date_iso", try pairs("date_iso"), string, ExtractorNormalize.dateISO)
        check("name", try pairs("name"), string, ExtractorNormalize.name)
        for row in try pairs("clean_edges") {
            total += 1
            let text = row[0] as! String, start = row[1] as! Int, end = row[2] as! Int, want = row[3] as! Bool
            let got = ExtractorDecode.cleanEdges(Array(text.unicodeScalars), start: start, end: end)
            if got != want {
                mismatches.append("clean_edges(\(text.debugDescription), \(start), \(end)): got \(got), want \(want)")
            }
        }
        report(mismatches, of: total, "normalize")
        XCTAssertGreaterThan(total, 0)
    }

    // MARK: decode

    /// `expected` in the decode and model fixtures; an absent key is nil.
    private struct Fields: Decodable, Equatable, CustomStringConvertible {
        var is_txn: Bool
        var direction: String?
        var amount_paise: Int64?
        var ref: String?
        var payee: String?
        var vpa: String?
        var own_acct_tail: String?
        var cpty_acct_tail: String?
        var date_iso: String?
        var balance_paise: Int64?

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            is_txn = try c.decode(Bool.self, forKey: .is_txn)
            direction = try c.decodeIfPresent(String.self, forKey: .direction)
            amount_paise = try c.decodeIfPresent(Int64.self, forKey: .amount_paise)
            ref = try c.decodeIfPresent(String.self, forKey: .ref)
            payee = try c.decodeIfPresent(String.self, forKey: .payee)
            vpa = try c.decodeIfPresent(String.self, forKey: .vpa)
            own_acct_tail = try c.decodeIfPresent(String.self, forKey: .own_acct_tail)
            cpty_acct_tail = try c.decodeIfPresent(String.self, forKey: .cpty_acct_tail)
            date_iso = try c.decodeIfPresent(String.self, forKey: .date_iso)
            balance_paise = try c.decodeIfPresent(Int64.self, forKey: .balance_paise)
        }

        init(_ a: ExtractedAlert) {
            is_txn = a.isTransaction
            direction = a.direction?.rawValue
            amount_paise = a.amountPaise
            ref = a.ref
            payee = a.payee
            vpa = a.vpa
            own_acct_tail = a.ownAccountTail
            cpty_acct_tail = a.counterpartyAccountTail
            date_iso = a.dateISO
            balance_paise = a.balancePaise
        }

        private enum CodingKeys: String, CodingKey {
            case is_txn, direction, amount_paise, ref, payee, vpa, own_acct_tail, cpty_acct_tail, date_iso,
                 balance_paise
        }

        var description: String {
            let all: [(String, Any?)] = [("is_txn", is_txn), ("direction", direction), ("amount_paise", amount_paise),
                                         ("ref", ref), ("payee", payee), ("vpa", vpa),
                                         ("own_acct_tail", own_acct_tail), ("cpty_acct_tail", cpty_acct_tail),
                                         ("date_iso", date_iso), ("balance_paise", balance_paise)]
            return "{" + all.compactMap { k, v in v.map { "\(k): \($0)" } }.joined(separator: ", ") + "}"
        }
    }

    private struct DecodeFixture: Decodable {
        struct Case: Decodable {
            var text: String
            var offsets: [[Int]]
            var tag_logits: [[Double]]
            var seq_logits: [Double]
            var expected: Fields
        }
        var tags: [String]
        var seq_classes: [String]
        var cases: [Case]
    }

    func testDecodeMatchesReference() throws {
        let fixture = try JSONDecoder().decode(DecodeFixture.self, from: fixture("extractor-decode"))
        var mismatches: [String] = []
        for (index, testCase) in fixture.cases.enumerated() {
            let got = Fields(ExtractorDecode.decode(
                text: Array(testCase.text.unicodeScalars),
                offsets: testCase.offsets.map { ExtractorTokenizer.Offset(start: $0[0], end: $0[1]) },
                tagLogits: testCase.tag_logits, seqLogits: testCase.seq_logits,
                tags: fixture.tags, seqClasses: fixture.seq_classes))
            if got != testCase.expected {
                mismatches.append("case \(index) \(testCase.text.debugDescription.prefix(80)): " +
                                  "got \(got), want \(testCase.expected)")
            }
        }
        report(mismatches, of: fixture.cases.count, "decode")
        XCTAssertGreaterThan(fixture.cases.count, 0)
    }

    // MARK: end to end through Core ML

    private struct ModelFixture: Decodable {
        struct Case: Decodable {
            var text: String
            var expected: Fields
        }
        var cases: [Case]
    }

    #if canImport(CoreML)
    func testCoreMLPipelineMatchesReference() throws {
        let fixture = try JSONDecoder().decode(ModelFixture.self, from: fixture("extractor-model"))
        let loadStart = Date()
        let extractor = try AlertExtractor.live()
        let loadTime = Date().timeIntervalSince(loadStart)
        var mismatches: [String] = []
        var times: [TimeInterval] = []
        for (index, testCase) in fixture.cases.enumerated() {
            let start = Date()
            let alert = try extractor.extract(testCase.text)
            times.append(Date().timeIntervalSince(start))
            let got = Fields(alert)
            if got != testCase.expected {
                mismatches.append("case \(index) \(testCase.text.debugDescription.prefix(100)): got \(got), " +
                                  "want \(testCase.expected), class confidence \(alert.classConfidence)")
            }
        }
        let sorted = times.sorted()
        print(String(format: "extractor timing: model load %.1f ms, first extract %.1f ms, median %.1f ms, max %.1f ms over %d",
                     loadTime * 1000, times[0] * 1000, sorted[sorted.count / 2] * 1000,
                     sorted.last! * 1000, times.count))
        report(mismatches, of: fixture.cases.count, "model")
        XCTAssertGreaterThan(fixture.cases.count, 0)
    }
    #endif
}
