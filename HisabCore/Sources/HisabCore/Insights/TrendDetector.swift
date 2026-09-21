import Foundation

/// Category spend in the latest complete month against the average of the
/// preceding complete months. Both gates must clear — a percentage without
/// rupees is noise, and rupees without a percentage is just a big month.
public enum TrendDetector {
    public static func detect(records: [InsightRecord], month: YearMonth,
                              completeMonths: Set<YearMonth>,
                              monthDebitTotalPaise: Int64,
                              config: InsightsConfig) -> (insights: [Insight],
                                                          concentrationIDs: Set<String>) {
        let settings = config.trend
        let weight = config.ranker.weights[InsightKind.trend.rawValue] ?? 0

        var window: [YearMonth] = []
        var cursor = month.advanced(by: -1)
        var steps = 0
        while window.count < settings.windowMonths && steps < 24 {
            if completeMonths.contains(cursor) { window.append(cursor) }
            cursor = cursor.advanced(by: -1)
            steps += 1
        }
        guard !window.isEmpty else { return ([], []) }
        let windowSet = Set(window)

        let debits = records.filter { $0.direction == .debit }
        var currentRows: [String: [InsightRecord]] = [:]
        var baseline: [String: Int64] = [:]
        for row in debits {
            let rowMonth = YearMonth(date: row.date)
            if rowMonth == month {
                currentRows[row.category, default: []].append(row)
            } else if windowSet.contains(rowMonth) {
                baseline[row.category, default: 0] += row.amountPaise
            }
        }

        var insights: [Insight] = []
        var concentrationIDs: Set<String> = []
        // Sorted so output order never depends on dictionary iteration order.
        for category in currentRows.keys.sorted() {
            let rows = currentRows[category] ?? []
            let currentTotal = rows.reduce(Int64(0)) { $0 + $1.amountPaise }
            let baselineSum = baseline[category] ?? 0
            guard baselineSum > 0 else { continue }
            let average = baselineSum / Int64(window.count)
            guard average > 0 else { continue }
            let delta = currentTotal - average
            let pct = Int(delta * 100 / average)
            guard abs(pct) >= settings.minPct, abs(delta) >= settings.minAbsPaise else { continue }

            var detail = pct >= 0
                ? "up \(pct)% vs your \(window.count)-month average"
                : "down \(-pct)% vs your \(window.count)-month average"
            // Share of the month's category spend, not of the delta: a single
            // purchase clears most modest deltas, so share-of-delta would call
            // nearly every rise "driven by one payment".
            if delta > 0, let driver = rows.max(by: { $0.amountPaise < $1.amountPaise }),
               driver.amountPaise * 100 >= currentTotal * Int64(settings.concentrationPct) {
                detail += " — driven by one \(Money.formatPaise(driver.amountPaise))"
                    + " payment to \(driver.merchant)"
                concentrationIDs.insert(driver.id)
            }

            let magnitude = abs(delta) * 1000 / max(monthDebitTotalPaise, 1)
            insights.append(Insight(
                id: InsightID.make("trend|\(category)|\(month.description)|\(pct)"),
                kind: .trend,
                headline: "\(category): \(Money.formatPaise(currentTotal))",
                detail: detail,
                evidenceIDs: rows.map(\.id).sorted(),
                score: magnitude * weight,
                mute: .category(category)))
        }
        return (insights, concentrationIDs)
    }
}
