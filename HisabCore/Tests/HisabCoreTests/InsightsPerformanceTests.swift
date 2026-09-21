import XCTest
@testable import HisabCore

/// A wall-clock ceiling on one `InsightsEngine.generate` pass at a realistic
/// corpus size.
///
/// This exists because nothing else in either suite could see the defect it
/// guards: every unit fixture is tens of rows and the demo set is 205, while
/// the engine runs synchronously inside the dashboard's `body` — on first
/// paint, on every month-chip tap, on every dismiss. An `O(recent × history)`
/// merchant-normalize loop that is invisible at 205 rows froze the UI for
/// ~1–3 seconds at a year of statements.
///
/// Mirrored by `insights_performance_test.dart`; keep the generator and the
/// budget in step across the two cores.
final class InsightsPerformanceTests: XCTestCase {
    /// ~2 years of statements at ~200 transactions a month. Above any real
    /// user's corpus today, which is the point: the budget has to hold for
    /// the user who keeps importing.
    private static let recordCount = 5_000
    private static let perMonth = 200

    /// Budget for the best of three passes, chosen against measurements
    /// rather than a round number:
    ///
    /// - post-fix, `swift test` (debug, unoptimized) on an M-series Mac:
    ///   ~180 ms; release is a small fraction of that and the shipping app is
    ///   release.
    /// - pre-fix, same machine and configuration: ~2,900 ms.
    ///
    /// 1,000 ms sits ~5.5× above the observed cost and ~3× below the
    /// regression, so a slower CI box has room to be two to three times
    /// slower than this machine without flaking, while the quadratic-ish
    /// loop coming back fails the test outright. Best-of-three rather than a
    /// single pass: scheduler noise can only ever add time, so the minimum is
    /// the statistic that says what the work costs.
    private static let budgetMs: Double = 1_000

    private static let categories = ["Food", "Transport", "Shopping",
                                     "Bills", "Housing", "Health"]

    /// A fixed UTC instant, so the dataset is identical on every run and on
    /// both platforms. 12:00 UTC on the last day of the month is 17:30 IST,
    /// after every generated row's 12:00 IST.
    private func utc(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute
        return calendar.date(from: comps)!
    }

    /// Deterministic synthetic history: `perMonth` debits a month across 120
    /// merchants, walking backwards from `now`'s month. The LCG is the same
    /// one the Dart mirror uses, so both cores measure the same workload.
    private func records(_ count: Int, now: Date) -> [InsightRecord] {
        let pool = 120
        let merchants: [String] = (0..<pool).map { index in
            let first = Character(UnicodeScalar(97 + index / 26)!)
            let second = Character(UnicodeScalar(97 + index % 26)!)
            return "Merchant \(first)\(second)"
        }
        var seed = 987_654_321
        func next() -> Int {
            seed = (seed &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
            return seed
        }

        let base = YearMonth(date: now)
        var rows: [InsightRecord] = []
        rows.reserveCapacity(count)
        for index in 0..<count {
            let backwards = count - 1 - index
            let month = base.advanced(by: -(backwards / Self.perMonth))
            let day = 1 + (backwards % Self.perMonth) % 28
            let amount = Int64(10_000 + next() % 500_000)
            let merchant = merchants[next() % pool]
            rows.append(InsightRecord(
                id: "txn-\(index)",
                date: utc(month.year, month.month, day, 6, 30),
                amountPaise: amount,
                direction: .debit,
                category: Self.categories[index % Self.categories.count],
                merchant: merchant))
        }
        return rows
    }

    private func input(_ count: Int) -> InsightsInput {
        let now = utc(2026, 9, 30, 12, 0)
        let months = (count + Self.perMonth - 1) / Self.perMonth
        let current = YearMonth(date: now)
        let oldest = current.advanced(by: -(months - 1))
        return InsightsInput(
            records: records(count, now: now),
            documentPeriods: [DatePeriod(start: utc(oldest.year, oldest.month, 1),
                                         end: utc(current.year, current.month, 1))],
            now: now)
    }

    func testGeneratingInsightsForTwoYearsOfHistoryStaysUnderBudget() {
        let input = self.input(Self.recordCount)
        var best = Double.greatestFiniteMagnitude
        var cards = 0
        for _ in 0..<3 {
            let start = DispatchTime.now()
            let result = InsightsEngine.generate(input: input, config: .fallback,
                                                 suppressions: Suppressions())
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds
                                 - start.uptimeNanoseconds) / 1e6
            best = min(best, elapsed)
            cards = result.cards.count
        }
        // A pass that produced nothing would be free and prove nothing.
        XCTAssertGreaterThan(cards, 0)
        XCTAssertLessThan(best, Self.budgetMs,
                          "InsightsEngine.generate took \(Int(best.rounded())) ms for "
                          + "\(Self.recordCount) records; budget is "
                          + "\(Int(Self.budgetMs)) ms. See this file's doc comment.")
    }
}
