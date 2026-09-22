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
        // An Android notification *update* arrives seconds later. It must not
        // produce a second memo, so the hash keys on the day, not the instant.
        let morning = PendingMemo(amountPaise: 45_000, direction: .debit,
                                  payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                  accountTail: "1234",
                                  date: date("2026-09-22 09:15"),
                                  capturedAt: date("2026-09-22 09:15"))
        let seconds_later = PendingMemo(amountPaise: 45_000, direction: .debit,
                                        payee: "VEDANT SABOO", vpa: "vedant@okaxis",
                                        accountTail: "1234",
                                        date: date("2026-09-22 09:15"),
                                        capturedAt: date("2026-09-22 09:16"))
        XCTAssertEqual(morning.captureHash, seconds_later.captureHash)
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
