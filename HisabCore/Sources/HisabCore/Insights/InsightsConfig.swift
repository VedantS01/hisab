import Foundation

/// Tunable thresholds for the insight detectors. Bundled as
/// Resources/insights/insights-config.json and synced into the Flutter
/// assets — numbers only, never logic, so tuning ships by editing one
/// file rather than two codebases.
public struct InsightsConfig: Codable, Sendable, Equatable {
    public struct Trend: Codable, Sendable, Equatable {
        public var minPct: Int
        public var minAbsPaise: Int64
        public var windowMonths: Int
        public var concentrationPct: Int
    }

    public struct Recurrence: Codable, Sendable, Equatable {
        public var minOccurrences: Int
        public var monthlyMinDays: Int
        public var monthlyMaxDays: Int
        public var weeklyMinDays: Int
        public var weeklyMaxDays: Int
        public var amountSpreadPct: Int
        public var changedPct: Int
        public var newWithinMonths: Int
        /// A series counts as active while its last payment is within this
        /// many cadence-lengths of now; cancelled subscriptions age out.
        public var activeWithinCadences: Int
    }

    public struct Anomaly: Codable, Sendable, Equatable {
        public var outlierMultiple: Int
        public var outlierMinPaise: Int64
        public var minPriors: Int
        public var lookbackDays: Int
        public var duplicateWindowMinutes: Int
    }

    public struct Ranker: Codable, Sendable, Equatable {
        public var maxCards: Int
        public var maxPerType: Int
        /// Keyed by InsightKind.rawValue. Integers: scores must stay exact.
        public var weights: [String: Int64]
    }

    public var version: Int
    public var trend: Trend
    public var recurrence: Recurrence
    public var anomaly: Anomaly
    public var ranker: Ranker

    public static func bundled() -> InsightsConfig {
        if let url = Bundle.module.url(forResource: "insights-config", withExtension: "json",
                                       subdirectory: "Resources/insights"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(InsightsConfig.self, from: data) {
            return config
        }
        return fallback
    }

    /// Mirrors the bundled JSON exactly; used only if the resource is missing.
    public static let fallback = InsightsConfig(
        version: 1,
        trend: Trend(minPct: 25, minAbsPaise: 50_000, windowMonths: 3,
                     concentrationPct: 70),
        recurrence: Recurrence(minOccurrences: 3, monthlyMinDays: 28, monthlyMaxDays: 33,
                               weeklyMinDays: 6, weeklyMaxDays: 8, amountSpreadPct: 15,
                               changedPct: 10, newWithinMonths: 2, activeWithinCadences: 2),
        anomaly: Anomaly(outlierMultiple: 3, outlierMinPaise: 100_000, minPriors: 5,
                         lookbackDays: 35, duplicateWindowMinutes: 10),
        ranker: Ranker(maxCards: 5, maxPerType: 3,
                       weights: ["possibleDuplicate": 4, "recurringNew": 3,
                                 "recurringChanged": 3, "outlierAmount": 2,
                                 "trend": 1, "committedSpend": 0]))
}
