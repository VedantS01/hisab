import XCTest
@testable import HisabCore

final class PendingMemoTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    func testCaptureHashIgnoresTimeOfDay() {
        // Two captures of the same underlying payment, with `date` values
        // minutes (or hours) apart but on the same IST calendar day — e.g. an
        // alert with no date in its text, where AlertParser falls back to
        // receivedAt, and a second capture lands later. The hash must key on
        // the day, not the instant, so these collapse to one memo.
        let morning = PendingMemo(amountPaise: 45_000, direction: .debit,
                                  payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                  accountTail: "1234",
                                  date: date("2026-09-22 09:15"),
                                  capturedAt: date("2026-09-22 09:15"))
        let sameDayLater = PendingMemo(amountPaise: 45_000, direction: .debit,
                                       payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                       accountTail: "1234",
                                       date: date("2026-09-22 23:50"),
                                       capturedAt: date("2026-09-22 23:50"))
        XCTAssertEqual(morning.captureHash, sameDayLater.captureHash)
    }

    func testCaptureHashSeparatesAcrossISTMidnight() {
        // The other half of day granularity: `date` values only minutes apart
        // but on different IST calendar days must NOT collapse.
        let beforeMidnight = PendingMemo(amountPaise: 45_000, direction: .debit,
                                         payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                         accountTail: "1234",
                                         date: date("2026-09-22 23:55"),
                                         capturedAt: date("2026-09-22 23:55"))
        let afterMidnight = PendingMemo(amountPaise: 45_000, direction: .debit,
                                        payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                        accountTail: "1234",
                                        date: date("2026-09-23 00:05"),
                                        capturedAt: date("2026-09-23 00:05"))
        XCTAssertNotEqual(beforeMidnight.captureHash, afterMidnight.captureHash)
    }

    func testCaptureHashSeparatesAmountPayeeAndVPA() {
        // captureHash IS the dedup identity — each field that feeds it must
        // move the hash when it changes.
        let baseline = PendingMemo(amountPaise: 45_000, direction: .debit,
                                   payee: "SWIGGY", vpa: "swiggy@icici",
                                   accountTail: "1234",
                                   date: date("2026-09-22 09:15"),
                                   capturedAt: date("2026-09-22 09:15"))

        let differentAmount = PendingMemo(amountPaise: 45_001, direction: .debit,
                                          payee: "SWIGGY", vpa: "swiggy@icici",
                                          accountTail: "1234",
                                          date: date("2026-09-22 09:15"),
                                          capturedAt: date("2026-09-22 09:15"))
        XCTAssertNotEqual(baseline.captureHash, differentAmount.captureHash)

        let differentPayee = PendingMemo(amountPaise: 45_000, direction: .debit,
                                         payee: "ZOMATO", vpa: "swiggy@icici",
                                         accountTail: "1234",
                                         date: date("2026-09-22 09:15"),
                                         capturedAt: date("2026-09-22 09:15"))
        XCTAssertNotEqual(baseline.captureHash, differentPayee.captureHash)

        let differentVPA = PendingMemo(amountPaise: 45_000, direction: .debit,
                                       payee: "SWIGGY", vpa: "swiggy@hdfcbank",
                                       accountTail: "1234",
                                       date: date("2026-09-22 09:15"),
                                       capturedAt: date("2026-09-22 09:15"))
        XCTAssertNotEqual(baseline.captureHash, differentVPA.captureHash)
    }

    func testCaptureHashSeparatesDirection() {
        // A refund reuses the payee and amount; it is a different movement.
        let debit = PendingMemo(amountPaise: 45_000, direction: .debit,
                                payee: "SWIGGY", vpa: nil, accountTail: nil,
                                date: date("2026-09-22 09:15"),
                                capturedAt: date("2026-09-22 09:15"))
        let credit = PendingMemo(amountPaise: 45_000, direction: .credit,
                                 payee: "SWIGGY", vpa: nil, accountTail: nil,
                                 date: date("2026-09-22 09:15"),
                                 capturedAt: date("2026-09-22 09:15"))
        XCTAssertNotEqual(debit.captureHash, credit.captureHash)
    }

    func testPayeeNormalizedMatchesSuggestionEngine() {
        // Rule patterns must match what the existing rule store already holds.
        let memo = PendingMemo(amountPaise: 1, direction: .debit,
                               payee: "BLUE TOKAI COFFEE ROASTERS PVT", vpa: nil,
                               accountTail: nil, date: date("2026-09-22 09:15"),
                               capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(memo.payeeNormalized, "blue tokai coffee")
    }

    func testRuleKeyPrefersVPAOverUnstableDisplayName() {
        // The whole point: "VEDANT SABOO" varies per statement, the VPA does not.
        let withVPA = PendingMemo(amountPaise: 1, direction: .debit,
                                  payee: "VEDANT SABOO", vpa: "Vedant@OkAxis",
                                  accountTail: nil, date: date("2026-09-22 09:15"),
                                  capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(withVPA.ruleKey, RuleKey(pattern: "vedant@okaxis", kind: .vpa))

        let withoutVPA = PendingMemo(amountPaise: 1, direction: .debit,
                                     payee: "Blue Tokai", vpa: nil,
                                     accountTail: nil, date: date("2026-09-22 09:15"),
                                     capturedAt: date("2026-09-22 09:15"))
        XCTAssertEqual(withoutVPA.ruleKey, RuleKey(pattern: "blue tokai", kind: .merchant))
    }
}
