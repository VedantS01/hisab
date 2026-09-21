import XCTest
@testable import HisabCore

final class InsightsConfigTests: XCTestCase {
    func testBundledConfigLoadsWithSaneValues() {
        let config = InsightsConfig.bundled()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.trend.minPct, 25)
        XCTAssertEqual(config.trend.minAbsPaise, 50_000)
        XCTAssertEqual(config.recurrence.minOccurrences, 3)
        XCTAssertEqual(config.anomaly.lookbackDays, 35)
        XCTAssertEqual(config.ranker.maxCards, 5)
        XCTAssertEqual(config.ranker.maxPerType, 3)
    }

    func testBundledConfigMatchesTheCompiledFallback() {
        // The fallback exists only for a missing resource; if the two ever
        // diverge, tuning would silently depend on which one loaded.
        XCTAssertEqual(InsightsConfig.bundled(), InsightsConfig.fallback)
    }

    // Uncommented in Task 2
    // func testEveryInsightKindHasARankerWeight() {
    //     let config = InsightsConfig.bundled()
    //     for kind in InsightKind.allCases {
    //         XCTAssertNotNil(config.ranker.weights[kind.rawValue],
    //                         "missing ranker weight for \(kind.rawValue)")
    //     }
    // }
}
