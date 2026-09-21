import XCTest
@testable import HisabCore

final class InsightsEngineTests: XCTestCase {
    private let config = InsightsConfig.fallback

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func record(_ id: String, _ iso: String, _ paise: Int64,
                        _ category: String, _ merchant: String) -> InsightRecord {
        InsightRecord(id: id, date: day(iso), amountPaise: paise, direction: .debit,
                      category: category, merchant: merchant)
    }

    /// Jan–Aug complete, "now" mid-September: August is the latest complete
    /// month. The period has to end at 2026-09-01 00:00 IST, because August's
    /// last instant is 2026-08-31 23:59:59 — a period ending at 2026-08-31
    /// 00:00 leaves August incomplete and every August assertion vacuous.
    private var periods: [DatePeriod] {
        [DatePeriod(start: day("2026-01-01"), end: day("2026-09-01"))]
    }
    private var now: Date { day("2026-09-15") }

    /// A rent series (recurring), a Food trend, and a duplicate pair.
    private var dataset: [InsightRecord] {
        var rows: [InsightRecord] = []
        for (index, month) in ["06", "07", "08"].enumerated() {
            rows.append(record("rent\(index)", "2026-\(month)-05", 1_500_000, "Housing", "Landlord"))
            rows.append(record("food\(index)", "2026-\(month)-12", 100_000, "Food", "Swiggy"))
        }
        rows.append(record("foodspike", "2026-08-20", 300_000, "Food", "Swiggy"))
        rows.append(record("dup1", "2026-08-25", 45_000, "Food", "Zomato"))
        rows.append(record("dup2", "2026-08-25", 45_000, "Food", "Zomato"))
        return rows
    }

    private func generate(_ suppressions: Suppressions = Suppressions()) -> InsightsResult {
        InsightsEngine.generate(
            input: InsightsInput(records: dataset, documentPeriods: periods, now: now),
            config: config, suppressions: suppressions)
    }

    func testCommittedSpendIsAlwaysTheLastCard() {
        let result = generate()
        XCTAssertFalse(result.cards.isEmpty)
        XCTAssertEqual(result.cards.last?.kind, .committedSpend)
        XCTAssertEqual(result.cards.filter { $0.kind == .committedSpend }.count, 1)
    }

    func testCardsAreCappedAtMaxCards() {
        XCTAssertLessThanOrEqual(generate().cards.count, config.ranker.maxCards)
    }

    /// Ranking is score descending, id ascending as the tie-break — kind
    /// weight only feeds the score, it is not a separate sort key.
    func testCardsAreOrderedByScoreThenID() {
        let ranked = generate().cards.filter { $0.kind != .committedSpend }
        XCTAssertGreaterThan(ranked.count, 1)
        for index in 1..<ranked.count {
            let previous = ranked[index - 1]
            let current = ranked[index]
            if previous.score == current.score {
                XCTAssertLessThan(previous.id, current.id,
                                  "equal scores must tie-break on id ascending")
            } else {
                XCTAssertGreaterThan(previous.score, current.score,
                                     "cards must be ordered by score descending")
            }
        }
    }

    func testDismissedIDsAreRemovedButStillReportedInAllIDs() {
        let first = generate().cards[0]
        let result = generate(Suppressions(dismissedIDs: [first.id]))
        XCTAssertFalse(result.cards.contains { $0.id == first.id })
        XCTAssertTrue(result.allIDs.contains(first.id),
                      "allIDs must list every generated id so the app can prune")
    }

    func testMutingAMerchantSilencesItsCards() {
        let result = generate(Suppressions(mutedMerchants: ["zomato"]))
        XCTAssertFalse(result.cards.contains { $0.kind == .possibleDuplicate })
    }

    func testMutingACategorySilencesItsTrend() {
        let result = generate(Suppressions(mutedCategories: ["Food"]))
        // The dataset also trends Housing, which muting Food must not touch.
        XCTAssertFalse(result.cards.contains {
            $0.kind == .trend && $0.headline.hasPrefix("Food")
        })
        XCTAssertTrue(result.cards.contains {
            $0.kind == .trend && $0.headline.hasPrefix("Housing")
        })
    }

    func testAnOutlierOnARecurringPaymentIsSuppressed() {
        // Six monthly payments plus a spike inside the 35-day anomaly
        // lookback: the recurrence card claims the spike, so no outlier card.
        var rows: [InsightRecord] = []
        for index in 1...6 {
            rows.append(record("g\(index)", "2026-0\(index)-05", 200_000, "Bills", "Gym"))
        }
        rows.append(record("spike", "2026-09-05", 900_000, "Bills", "Gym"))
        let result = InsightsEngine.generate(
            input: InsightsInput(records: rows, documentPeriods: periods, now: now),
            config: config, suppressions: Suppressions())
        XCTAssertTrue(result.cards.contains { $0.kind == .recurringChanged },
                      "the recurrence card must be the one that owns the spike")
        XCTAssertFalse(result.cards.contains { $0.kind == .outlierAmount })
    }

    func testADuplicatedOutlierIsOneDuplicateCardNotTwoOutliers() {
        // Five priors set a typical amount; the same recent day then carries
        // two identical charges, each an outlier on its own. "You may have
        // paid twice" supersedes "that was unusually large", twice over.
        var rows: [InsightRecord] = []
        for index in 2...6 {
            rows.append(record("prior\(index)", "2026-08-1\(index)", 30_000, "Shopping", "Acme"))
        }
        rows.append(record("twin1", "2026-09-10", 200_000, "Shopping", "Acme"))
        rows.append(record("twin2", "2026-09-10", 200_000, "Shopping", "Acme"))
        let result = InsightsEngine.generate(
            input: InsightsInput(records: rows, documentPeriods: periods, now: now),
            config: config, suppressions: Suppressions())
        XCTAssertTrue(result.cards.contains { $0.kind == .possibleDuplicate })
        XCTAssertFalse(result.cards.contains { $0.kind == .outlierAmount },
                       "a possible-duplicate card supersedes outliers on the same rows")
    }

    func testWithoutACompleteMonthNoTrendCardsAppear() {
        let partial = [DatePeriod(start: day("2026-08-15"), end: day("2026-09-14"))]
        let result = InsightsEngine.generate(
            input: InsightsInput(records: dataset, documentPeriods: partial, now: now),
            config: config, suppressions: Suppressions())
        XCTAssertFalse(result.cards.contains { $0.kind == .trend })
    }
}
