import Foundation

/// The single entry point the apps call: transactions in, ranked cards out.
/// Pure and stateless — insights are recomputed at every boot and import
/// rather than stored, so the only persisted state is what the user
/// dismissed or muted.
public enum InsightsEngine {
    public static func generate(input: InsightsInput, config: InsightsConfig,
                                suppressions: Suppressions) -> InsightsResult {
        let completeMonths = CompleteMonths.of(input.documentPeriods)
        let latest = CompleteMonths.latest(input.documentPeriods, notAfter: input.now)

        var monthDebitTotal: Int64 = 0
        if let month = latest {
            for row in input.records
            where row.direction == .debit && YearMonth(date: row.date) == month {
                monthDebitTotal += row.amountPaise
            }
        }

        var trends: [Insight] = []
        var concentrationIDs: Set<String> = []
        if let month = latest {
            (trends, concentrationIDs) = TrendDetector.detect(
                records: input.records, month: month, completeMonths: completeMonths,
                monthDebitTotalPaise: monthDebitTotal, config: config)
        }
        let (recurrences, claimedIDs) = RecurrenceDetector.detect(
            records: input.records, now: input.now,
            monthDebitTotalPaise: monthDebitTotal, config: config)
        let anomalies = AnomalyDetector.detect(
            records: input.records, now: input.now,
            monthDebitTotalPaise: monthDebitTotal, config: config)

        // One event, one card: a recurring payment or a trend's dominant
        // purchase is already explained — don't also call it unusual.
        var explained = claimedIDs.union(concentrationIDs)
        // The two anomaly passes are independent, so a row that is both
        // duplicated and unusually large would produce two cards about one
        // event. "You may have paid twice" is the more actionable reading,
        // so a possible-duplicate card supersedes an outlier on its rows.
        for insight in anomalies where insight.kind == .possibleDuplicate {
            explained.formUnion(insight.evidenceIDs)
        }
        let deduped = anomalies.filter { insight in
            guard insight.kind == .outlierAmount else { return true }
            return !insight.evidenceIDs.contains { explained.contains($0) }
        }

        let everything = trends + recurrences + deduped
        // allIDs covers every card this pass generated, collision-suppressed
        // ones included, so a dismissal survives a suppression that later
        // lifts rather than being pruned while its card is merely hidden.
        let allIDs = Set((trends + recurrences + anomalies).map(\.id))

        let surviving = everything.filter { insight in
            guard !suppressions.dismissedIDs.contains(insight.id) else { return false }
            switch insight.mute {
            case .merchant(let key): return !suppressions.mutedMerchants.contains(key)
            case .category(let name): return !suppressions.mutedCategories.contains(name)
            case nil: return true
            }
        }

        let committed = surviving.filter { $0.kind == .committedSpend }
        let ranked = surviving
            .filter { $0.kind != .committedSpend }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.id < rhs.id : lhs.score > rhs.score
            }

        let budget = config.ranker.maxCards - (committed.isEmpty ? 0 : 1)
        var perKind: [InsightKind: Int] = [:]
        var cards: [Insight] = []
        for insight in ranked {
            guard cards.count < budget else { break }
            let used = perKind[insight.kind] ?? 0
            guard used < config.ranker.maxPerType else { continue }
            perKind[insight.kind] = used + 1
            cards.append(insight)
        }
        cards.append(contentsOf: committed.prefix(1))
        return InsightsResult(cards: cards, allIDs: allIDs)
    }
}
