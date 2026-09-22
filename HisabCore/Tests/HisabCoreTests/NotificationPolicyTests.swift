import XCTest
@testable import HisabCore

final class NotificationPolicyTests: XCTestCase {
    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func testSendsDuringWakingHoursUnderTheCap() {
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"), sentToday: 3), .send)
    }

    func testSuppressesAtTheDailyCap() {
        // A heavy UPI day must not turn into 40 notifications.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"),
                                                 sentToday: NotificationPolicy.dailyCap),
                       .suppress)
    }

    func testHoldsLateNightUntilMorning() {
        // Hisab must never wake anyone. 23:10 -> 08:00 next day.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 23:10"), sentToday: 0),
                       .hold(until: at("2026-09-23 08:00")))
    }

    func testHoldsEarlyMorningUntilSameDayEight() {
        // 02:30 is still "last night" -> 08:00 the SAME day, not the next.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 02:30"), sentToday: 0),
                       .hold(until: at("2026-09-22 08:00")))
    }

    func testSendsExactlyAtEightAndHoldsExactlyAtTwentyTwo() {
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 08:00"), sentToday: 0), .send)
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 22:00"), sentToday: 0),
                       .hold(until: at("2026-09-23 08:00")))
    }

    func testTheConstantsAreWhatTheyClaim() {
        // Asserted literally, because the behavioural tests below cannot see a
        // change in either value on their own: the cap test is self-referential
        // and no test exercises the 15:00-21:00 gap. A deliberate constant
        // deserves a guard that fails the moment it moves.
        XCTAssertEqual(NotificationPolicy.dailyCap, 10)
        XCTAssertEqual(NotificationPolicy.quietStartHour, 22)
        XCTAssertEqual(NotificationPolicy.quietEndHour, 8)
    }

    func testSendsJustUnderTheCapAndSuppressesAtIt() {
        // Literal 9 and 10, NOT NotificationPolicy.dailyCap — using the
        // constant here is what made the original test tautological.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"), sentToday: 9),
                       .send)
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 14:30"), sentToday: 10),
                       .suppress)
    }

    func testSendsThroughTheEveningUntilTwentyTwo() {
        // Closes the 15:00-21:00 blind spot: without this, quietStartHour could
        // be any value from 15 to 22 and the suite would not notice.
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 20:00"), sentToday: 0),
                       .send)
        XCTAssertEqual(NotificationPolicy.decide(now: at("2026-09-22 21:59"), sentToday: 0),
                       .send)
    }
}

final class CategoryRankerTests: XCTestCase {
    private func day(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso)!
    }

    private func record(_ category: String, _ date: String,
                        _ direction: Direction = .debit) -> SpendRecord {
        SpendRecord(merchant: "m", amountPaise: 100, date: day(date),
                    direction: direction, effectiveCategory: category)
    }

    func testRanksByCountAndExcludesNonCategories() {
        let now = day("2026-09-22")
        let records = [
            record("Food Delivery", "2026-09-20"), record("Food Delivery", "2026-09-19"),
            record("Food Delivery", "2026-09-18"),
            record("Transport", "2026-09-20"), record("Transport", "2026-09-19"),
            record("Shopping", "2026-09-20"),
            record("Groceries", "2026-09-20"),
            // These three must never be offered as an answer.
            record(Categorizer.uncategorized, "2026-09-20"),
            record(Categorizer.miscellaneous, "2026-09-20"),
            record(Categorizer.selfTransfer, "2026-09-20"),
        ]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Food Delivery", "Transport", "Groceries"],
                       "count desc, then alphabetical: Groceries before Shopping")
    }

    func testIgnoresRecordsOlderThanNinetyDaysAndCredits() {
        let now = day("2026-09-22")
        let records = [
            record("Food Delivery", "2026-01-01"),
            record("Transport", "2026-09-20", .credit),
            record("Shopping", "2026-09-20"),
        ]
        // AMENDED (task 11a): one real category plus the P2 seed top-up. What
        // this test pins is unchanged — Shopping is the ONLY history-derived
        // entry, and it leads. Without the window and credit filters the
        // history part would read ["Food Delivery", "Shopping", "Transport"].
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Shopping", "Food Delivery", "Groceries"])
    }

    // AMENDED (controller): the two tests above cannot distinguish a correct
    // implementation from two plausible wrong ones. Both of these must be
    // written, and both must be shown to fail against a deliberately wrong
    // implementation at least once - see "On discriminating tests" below.

    func testRanksByCountNotBySpend() {
        // The doc comment claims count beats spend precisely so one large
        // payment cannot outrank a habit. Every record in the tests above has
        // the same amount, so a ranker that summed PAISE would pass them all.
        let now = day("2026-09-22")
        let records = [
            SpendRecord(merchant: "m", amountPaise: 5_000_00, date: day("2026-09-20"),
                        direction: .debit, effectiveCategory: "Shopping"),
            record("Transport", "2026-09-20"),
            record("Transport", "2026-09-19"),
            record("Transport", "2026-09-18"),
        ]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 2),
                       ["Transport", "Shopping"],
                       "3 small debits must outrank 1 large one")
    }

    func testWindowBoundaryIsNinetyDays() {
        // The existing window test uses a record 264 days old, which would
        // pass against windowDays = 1 or 200 alike - it pins nothing.
        let now = day("2026-09-22")
        let inside = now.addingTimeInterval(-89 * 86_400)
        let outside = now.addingTimeInterval(-91 * 86_400)
        let records = [
            SpendRecord(merchant: "m", amountPaise: 100, date: inside,
                        direction: .debit, effectiveCategory: "Transport"),
            SpendRecord(merchant: "m", amountPaise: 100, date: outside,
                        direction: .debit, effectiveCategory: "Shopping"),
        ]
        // AMENDED (task 11a): trailing two entries are the P2 seed top-up. A
        // window wide enough to admit the 91-day row would put Shopping first
        // (count tie, alphabetical), so this still discriminates.
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Transport", "Food Delivery", "Groceries"],
                       "89 days old is inside the window, 91 days old is outside")
    }

    // MARK: - P2: the buttons must never be empty for a capture-only user

    // AMENDED (task 11a): this used to be `testReturnsFewerThanLimitWhenNotEnoughHistory`,
    // asserting that empty history returns []. That behaviour was the P2 defect:
    // `suggestionRecords` draws only from imported statements, so a user who
    // relies on capture and has never imported got a Later-only notification
    // forever. The expectation changed deliberately; the test was not bent to
    // fit new code.

    func testEmptyHistoryFallsBackToSeedCategories() {
        XCTAssertEqual(CategoryRanker.topCategories(records: [], now: day("2026-09-22"), limit: 3),
                       ["Food Delivery", "Groceries", "Transport"],
                       "a user who has never imported must still get three buttons")
    }

    func testPartialHistoryIsToppedUpWithoutBeingDisplacedOrDuplicated() {
        // "Shopping" is both the only real history AND a seed category, so this
        // pins two things at once: history keeps first place, and the top-up
        // does not offer the same category twice.
        let now = day("2026-09-22")
        let records = [record("Shopping", "2026-09-20")]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Shopping", "Food Delivery", "Groceries"])
    }

    func testFullHistoryIsUntouchedByTheFallback() {
        // Three real categories fill the limit, so no seed category may appear
        // — the fallback must not reorder or dilute a user who has history.
        let now = day("2026-09-22")
        let records = [
            record("Rent", "2026-09-20"), record("Rent", "2026-09-19"),
            record("Tuition", "2026-09-20"), record("Tuition", "2026-09-19"),
            record("Gifts", "2026-09-20"),
        ]
        XCTAssertEqual(CategoryRanker.topCategories(records: records, now: now, limit: 3),
                       ["Rent", "Tuition", "Gifts"])
    }

    func testFallbackNeverOffersTheThreeNonAnswers() {
        let all = CategoryRanker.topCategories(records: [], now: day("2026-09-22"), limit: 50)
        XCTAssertFalse(all.contains(Categorizer.uncategorized))
        XCTAssertFalse(all.contains(Categorizer.miscellaneous))
        XCTAssertFalse(all.contains(Categorizer.selfTransfer))
        XCTAssertEqual(Set(all).count, all.count, "no duplicates")
        XCTAssertFalse(all.isEmpty)
    }

    func testAZeroLimitAsksForNothingAndGetsNothing() {
        // `prefix(limit)` traps on a negative length and the top-up loop would
        // otherwise be the only guard.
        XCTAssertEqual(CategoryRanker.topCategories(records: [], now: day("2026-09-22"), limit: 0),
                       [])
    }
}
