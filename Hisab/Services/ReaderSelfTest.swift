#if DEBUG
import Foundation
import HisabCore

/// `--reader-selftest`: the on-device half of `AlertExtractorTests`, for a
/// phone, where SwiftPM tests cannot run. Every input length twice (iOS 27's
/// float16 CPU path crashed or returned NaN at some), then known alerts
/// against their expected reading — one of them exactly 64 tokens, the
/// default shape the Neural Engine plan misread.
enum ReaderSelfTest {
    private static let cases: [(text: String, direction: Direction?, amountPaise: Int64?, ref: String?)] = [
        ("Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. UPI Ref No 627775786529",
         .debit, 45_000, "627775786529"),
        ("UPDATE: an amount of INR 8,26,629 was credited in Acct **1169 by NEFT from SAXENA PVT LTD (08/05/2026 12:10) UPI:234811263430\nTotal Avail.Bal:INR 788.00",
         .credit, 82_662_900, "234811263430"),
        ("Your OTP for login is 482913. Do not share it with anyone.", nil, nil, nil),
    ]

    static func run() -> String {
        let model: CoreMLExtractorModel
        let extractor: AlertExtractor
        do {
            model = try CoreMLExtractorModel()
            extractor = try AlertExtractor(model: model)
        } catch {
            return "READER-SELFTEST load failed: \(error)"
        }
        let start = Date()
        var runs = 0, nonFinite: [Int] = []
        for n in 2...192 {
            let ids = [Int32(101)] + (1..<(n - 1)).map { Int32(2000 + ($0 * 37) % 3000) } + [102]
            for _ in 0..<2 {
                runs += 1
                guard let out = try? model.logits(inputIDs: ids, attentionMask: [Int32](repeating: 1, count: n)),
                      out.seq.allSatisfy(\.isFinite), out.tags.allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
                    nonFinite.append(n)
                    continue
                }
            }
        }
        let perRun = Date().timeIntervalSince(start) / Double(runs) * 1000
        var wrong: [String] = []
        for c in cases {
            let got = try? extractor.extract(c.text)
            let ok = c.direction == nil
                ? got?.isTransaction == false
                : got?.isTransaction == true && got?.direction == c.direction
                    && got?.amountPaise == c.amountPaise && got?.ref == c.ref
            if !ok { wrong.append("\(c.text.prefix(30))… got \(got.map { "\($0)" } ?? "a throw")") }
        }
        return "READER-SELFTEST sweep \(runs - nonFinite.count)/\(runs) finite"
            + (nonFinite.isEmpty ? "" : " (bad at \(Set(nonFinite).sorted()))")
            + String(format: ", %.1f ms per read", perRun)
            + ", known alerts \(cases.count - wrong.count)/\(cases.count)"
            + (wrong.isEmpty ? "" : ": " + wrong.joined(separator: "; "))
    }
}
#endif
