import Foundation

/// Repeating payments: rent, SIPs, EMIs, subscriptions. A series needs
/// enough occurrences, a stable interval, and a stable amount — the latest
/// payment is allowed to deviate, because that deviation is the "changed"
/// signal we want to report.
public enum RecurrenceDetector {
    public static func series(records: [InsightRecord], now: Date,
                              config: InsightsConfig) -> [RecurringSeries] {
        let settings = config.recurrence
        var groups: [String: [InsightRecord]] = [:]
        for row in records where row.direction == .debit {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            groups[key, default: []].append(row)
        }

        var result: [RecurringSeries] = []
        for key in groups.keys.sorted() {
            // Date, then id: neither platform's sort is stable, so same-day
            // payments to one merchant need an explicit total order for both
            // cores to emit transactionIDs in the same sequence.
            let members = (groups[key] ?? []).sorted {
                $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
            }
            guard members.count >= settings.minOccurrences else { continue }

            var gaps: [Int] = []
            for index in 1..<members.count {
                gaps.append(ISTDay.daysBetween(members[index - 1].date, members[index].date))
            }
            let medianGap = median(gaps.map(Int64.init))
            let cadence: Cadence
            if medianGap >= Int64(settings.monthlyMinDays), medianGap <= Int64(settings.monthlyMaxDays) {
                cadence = .monthly
            } else if medianGap >= Int64(settings.weeklyMinDays), medianGap <= Int64(settings.weeklyMaxDays) {
                cadence = .weekly
            } else {
                continue
            }

            let medianAmount = median(members.map(\.amountPaise))
            guard medianAmount > 0 else { continue }
            let stable = members.filter {
                abs($0.amountPaise - medianAmount) * 100 <= medianAmount * Int64(settings.amountSpreadPct)
            }
            guard stable.count >= settings.minOccurrences else { continue }

            let lastSeen = members[members.count - 1].date
            let cadenceDays = cadence == .monthly ? settings.monthlyMaxDays : settings.weeklyMaxDays
            let staleAfter = cadenceDays * settings.activeWithinCadences
            guard ISTDay.daysBetween(lastSeen, now) <= staleAfter else { continue }

            // Most common raw spelling; ties resolve alphabetically, matching
            // SuggestionEngine's display choice.
            var rawCounts: [String: Int] = [:]
            for member in members { rawCounts[member.merchant, default: 0] += 1 }
            let display = rawCounts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key ?? key

            result.append(RecurringSeries(
                merchantKey: key,
                displayMerchant: display,
                cadence: cadence,
                medianPaise: medianAmount,
                monthlyEquivalentPaise: cadence == .monthly ? medianAmount : medianAmount * 52 / 12,
                firstSeen: members[0].date,
                lastSeen: lastSeen,
                count: members.count,
                transactionIDs: members.map(\.id)))
        }
        return result
    }

    public static func detect(records: [InsightRecord], now: Date,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> (insights: [Insight],
                                                          claimedIDs: Set<String>) {
        let settings = config.recurrence
        let weights = config.ranker.weights
        let found = series(records: records, now: now, config: config)
        guard !found.isEmpty else { return ([], []) }

        var insights: [Insight] = []
        var claimed: Set<String> = []
        let newCutoff = YearMonth(date: now).advanced(by: -settings.newWithinMonths)

        for entry in found {
            claimed.formUnion(entry.transactionIDs)
            let cadenceWord = entry.cadence == .monthly ? "per month" : "per week"

            if YearMonth(date: entry.firstSeen) >= newCutoff {
                let magnitude = entry.monthlyEquivalentPaise * 1000 / max(monthDebitTotalPaise, 1)
                insights.append(Insight(
                    id: InsightID.make("recurring-new|\(entry.merchantKey)|\(entry.medianPaise)"),
                    kind: .recurringNew,
                    headline: "New recurring: \(entry.displayMerchant)",
                    detail: "\(Money.formatPaise(entry.medianPaise)) \(cadenceWord)"
                        + " since \(YearMonth(date: entry.firstSeen).displayName)",
                    evidenceIDs: entry.transactionIDs,
                    score: magnitude * (weights[InsightKind.recurringNew.rawValue] ?? 0),
                    mute: .merchant(entry.merchantKey)))
                continue  // a brand-new series can't also be "changed"
            }

            // Debits only: the median is a debit-only figure, so the payment
            // measured against it must be one too — a refund sharing the
            // merchant key would otherwise drive the "usually" sentence.
            guard let latest = records
                .filter({ $0.direction == .debit
                          && SuggestionEngine.normalize($0.merchant) == entry.merchantKey })
                .max(by: { $0.date < $1.date }) else { continue }
            let drift = abs(latest.amountPaise - entry.medianPaise)
            if drift * 100 >= entry.medianPaise * Int64(settings.changedPct) {
                let magnitude = drift * 1000 / max(monthDebitTotalPaise, 1)
                insights.append(Insight(
                    id: InsightID.make("recurring-changed|\(entry.merchantKey)|\(latest.amountPaise)"),
                    kind: .recurringChanged,
                    headline: "\(entry.displayMerchant): \(Money.formatPaise(latest.amountPaise))",
                    detail: "usually \(Money.formatPaise(entry.medianPaise)) \(cadenceWord)",
                    evidenceIDs: entry.transactionIDs,
                    score: magnitude * (weights[InsightKind.recurringChanged.rawValue] ?? 0),
                    mute: .merchant(entry.merchantKey)))
            }
        }

        if found.count >= 2 {
            let total = found.reduce(Int64(0)) { $0 + $1.monthlyEquivalentPaise }
            insights.append(Insight(
                id: InsightID.make("committed|\(found.count)|\(total)"),
                kind: .committedSpend,
                headline: "\(Money.formatPaise(total)) per month committed",
                detail: "across \(found.count) recurring payments",
                evidenceIDs: found.flatMap(\.transactionIDs),
                series: found,
                score: 0,  // pinned last by the ranker, never ranked on merit
                mute: nil))
        }
        return (insights, claimed)
    }

    /// Lower median of a sorted copy; both platforms must agree exactly.
    static func median(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[(sorted.count - 1) / 2]
    }
}
