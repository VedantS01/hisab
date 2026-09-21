import Foundation

/// Two conservative signals over a short window: payments that look
/// accidentally repeated, and amounts far above what this merchant usually
/// costs. Both stay silent unless there's enough history to be sure.
public enum AnomalyDetector {
    public static func detect(records: [InsightRecord], now: Date,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> [Insight] {
        let settings = config.anomaly
        let weights = config.ranker.weights
        let debits = records.filter { $0.direction == .debit }
        let recent = debits.filter {
            $0.date <= now && ISTDay.daysBetween($0.date, now) <= settings.lookbackDays
        }
        guard !recent.isEmpty else { return [] }

        // Normalize each debit's merchant exactly once. The outlier loop below
        // needs "every earlier debit to this merchant"; filtering the whole
        // history per recent row made that O(recent × history) *normalize*
        // calls, which is seconds once a user has a year of statements. The
        // grouped lists keep `debits` order, so `priors` below is the same
        // list in the same order the filter produced.
        var debitsByKey: [String: [InsightRecord]] = [:]
        for row in debits {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            debitsByKey[key, default: []].append(row)
        }

        var insights: [Insight] = []
        let denominator = max(monthDebitTotalPaise, 1)

        // Possible duplicates: same merchant, same amount, same IST day.
        var buckets: [String: [InsightRecord]] = [:]
        for row in recent {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            buckets["\(key)|\(ISTDay.string(row.date))|\(row.amountPaise)", default: []].append(row)
        }
        for bucketKey in buckets.keys.sorted() {
            let members = (buckets[bucketKey] ?? []).sorted { $0.id < $1.id }
            guard members.count >= 2 else { continue }
            // When every row carries a clock time, insist they're minutes apart;
            // date-only statements can't support that test, so day equality stands.
            if members.allSatisfy({ hasClockTime($0.date) }) {
                let times = members.map(\.date).sorted()
                var close = false
                for index in 1..<times.count
                where times[index].timeIntervalSince(times[index - 1])
                    <= Double(settings.duplicateWindowMinutes * 60) {
                    close = true
                }
                guard close else { continue }
            }
            let sample = members[0]
            let merchantKey = SuggestionEngine.normalize(sample.merchant)
            let magnitude = sample.amountPaise * 1000 / denominator
            insights.append(Insight(
                id: InsightID.make("duplicate|\(members.map(\.id).joined(separator: ","))"),
                kind: .possibleDuplicate,
                headline: "\(sample.merchant): \(Money.formatPaise(sample.amountPaise))"
                    + " ×\(members.count)",
                detail: "\(members.count) identical payments on \(dayLabel(sample.date))",
                evidenceIDs: members.map(\.id),
                score: magnitude * (weights[InsightKind.possibleDuplicate.rawValue] ?? 0),
                mute: .merchant(merchantKey)))
        }

        // Outliers: this merchant has history, and this payment dwarfs it.
        for row in recent.sorted(by: { $0.id < $1.id }) {
            let key = SuggestionEngine.normalize(row.merchant)
            guard !key.isEmpty else { continue }
            let priors = (debitsByKey[key] ?? []).filter { $0.date < row.date }
            guard priors.count >= settings.minPriors else { continue }
            let typical = RecurrenceDetector.median(priors.map(\.amountPaise))
            guard typical > 0,
                  row.amountPaise >= typical * Int64(settings.outlierMultiple),
                  row.amountPaise >= settings.outlierMinPaise else { continue }
            let magnitude = row.amountPaise * 1000 / denominator
            insights.append(Insight(
                id: InsightID.make("outlier|\(row.id)"),
                kind: .outlierAmount,
                headline: "\(row.merchant): \(Money.formatPaise(row.amountPaise))",
                detail: "about \(row.amountPaise / typical)× your usual \(Money.formatPaise(typical))",
                evidenceIDs: [row.id],
                score: magnitude * (weights[InsightKind.outlierAmount.rawValue] ?? 0),
                mute: .merchant(key)))
        }
        return insights
    }

    /// Statement rows without a time parse to IST midnight; payment-app rows
    /// (GPay) carry a real clock time.
    static func hasClockTime(_ date: Date) -> Bool {
        let comps = YearMonth.istCalendar.dateComponents([.hour, .minute, .second], from: date)
        return (comps.hour ?? 0) != 0 || (comps.minute ?? 0) != 0 || (comps.second ?? 0) != 0
    }

    static func dayLabel(_ date: Date) -> String { ISTDay.label(date) }
}
