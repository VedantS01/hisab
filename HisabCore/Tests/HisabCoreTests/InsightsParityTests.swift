import XCTest
@testable import HisabCore

/// One schema, several cases, two languages. Each fixture file pins the cards
/// *and* the full set of generated ids for one input, and the Dart suite
/// asserts the same files — so copy, ordering, scores and suppression
/// bookkeeping cannot drift on one platform only.
///
/// Set INSIGHTS_GT_OUT to a *directory* to regenerate every case's `expected`
/// and `expectedAllIDs` blocks (same env-gated dump pattern as
/// SamplesGroundTruthDump); the files land there under their fixture names.
final class InsightsParityTests: XCTestCase {
    /// Every case the two cores must agree on. Add a file here and in the
    /// Dart suite's matching list; nothing else needs to change.
    static let cases = ["insights-parity", "insights-parity-2", "insights-parity-3"]

    private struct Fixture: Codable {
        struct Row: Codable {
            let id: String
            let date: String
            let amountPaise: Int64
            let direction: String
            let category: String
            let merchant: String
        }
        struct Period: Codable {
            let start: String
            let end: String
        }
        struct Expected: Codable, Equatable {
            let id: String
            let kind: String
            let headline: String
            let detail: String
            let score: Int64
        }
        /// Absent entirely, or with any field absent, means "none".
        struct Suppress: Codable {
            var dismissedIDs: [String]?
            var mutedMerchants: [String]?
            var mutedCategories: [String]?
        }
        let now: String
        let periods: [Period]
        let records: [Row]
        var suppressions: Suppress?
        var expected: [Expected]
        /// Sorted, so the comparison doesn't depend on Set iteration order.
        var expectedAllIDs: [String]
    }

    private func parse(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testFixtureOutputIsStable() throws {
        let dumpDir = ProcessInfo.processInfo.environment["INSIGHTS_GT_OUT"]

        for name in Self.cases {
            let url = try XCTUnwrap(Bundle.module.url(forResource: name,
                                                      withExtension: "json",
                                                      subdirectory: "Fixtures"),
                                    "missing fixture \(name).json")
            var fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
            let input = InsightsInput(
                records: fixture.records.map {
                    InsightRecord(id: $0.id, date: parse($0.date), amountPaise: $0.amountPaise,
                                  direction: $0.direction == "credit" ? .credit : .debit,
                                  category: $0.category, merchant: $0.merchant)
                },
                documentPeriods: fixture.periods.map {
                    DatePeriod(start: parse($0.start), end: parse($0.end))
                },
                now: parse(fixture.now))
            let suppressions = Suppressions(
                dismissedIDs: Set(fixture.suppressions?.dismissedIDs ?? []),
                mutedMerchants: Set(fixture.suppressions?.mutedMerchants ?? []),
                mutedCategories: Set(fixture.suppressions?.mutedCategories ?? []))

            let result = InsightsEngine.generate(input: input, config: .fallback,
                                                 suppressions: suppressions)
            let actual = result.cards.map {
                Fixture.Expected(id: $0.id, kind: $0.kind.rawValue, headline: $0.headline,
                                 detail: $0.detail, score: $0.score)
            }
            let actualAllIDs = result.allIDs.sorted()

            if let dumpDir {
                fixture.expected = actual
                fixture.expectedAllIDs = actualAllIDs
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var data = try encoder.encode(fixture)
                data.append(0x0A)  // keep the committed blob newline-terminated
                let out = URL(fileURLWithPath: dumpDir).appendingPathComponent("\(name).json")
                try data.write(to: out)
                print("\(name): wrote \(actual.count) cards, \(actualAllIDs.count) ids to \(out.path)")
                continue
            }

            XCTAssertFalse(fixture.expectedAllIDs.isEmpty,
                           "\(name): no expected output — regenerate with INSIGHTS_GT_OUT")
            XCTAssertEqual(actual, fixture.expected, "\(name): cards differ")
            XCTAssertEqual(actualAllIDs, fixture.expectedAllIDs, "\(name): allIDs differ")
        }
    }
}
