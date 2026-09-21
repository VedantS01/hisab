import XCTest
@testable import HisabCore

/// One fixture, two languages. Set INSIGHTS_GT_OUT to regenerate the
/// `expected` block (same pattern as SamplesGroundTruthDump).
final class InsightsParityTests: XCTestCase {
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
        let now: String
        let periods: [Period]
        let records: [Row]
        var expected: [Expected]
    }

    private func parse(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testFixtureOutputIsStable() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "insights-parity",
                                                  withExtension: "json",
                                                  subdirectory: "Fixtures"))
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

        let result = InsightsEngine.generate(input: input, config: .fallback,
                                             suppressions: Suppressions())
        let actual = result.cards.map {
            Fixture.Expected(id: $0.id, kind: $0.kind.rawValue, headline: $0.headline,
                             detail: $0.detail, score: $0.score)
        }

        if let out = ProcessInfo.processInfo.environment["INSIGHTS_GT_OUT"] {
            fixture.expected = actual
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(fixture).write(to: URL(fileURLWithPath: out))
            print("wrote \(actual.count) expected insights to \(out)")
            return
        }

        XCTAssertFalse(fixture.expected.isEmpty,
                       "fixture has no expected output — regenerate with INSIGHTS_GT_OUT")
        XCTAssertEqual(actual, fixture.expected)
    }
}
