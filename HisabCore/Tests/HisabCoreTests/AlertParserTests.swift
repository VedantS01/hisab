import XCTest
@testable import HisabCore

final class AlertParserTests: XCTestCase {
    private func at(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }
    private let now = "2026-09-22 14:30"

    func testParsesHDFCStyleUPIDebit() {
        let text = "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. Ref 123456789012. Not you? Call 18002586161"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.amountPaise, 45_000)
        XCTAssertEqual(memo?.direction, .debit)
        XCTAssertEqual(memo?.vpa, "vedant@okaxis")
        XCTAssertEqual(memo?.accountTail, "1234")
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-22")
    }

    func testParsesLakhGroupedAmount() {
        let text = "INR 1,23,456.78 debited from A/c no. XX9876 towards BLUE TOKAI COFFEE on 21/09/2026"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.amountPaise, 12_345_678)
        XCTAssertEqual(memo?.payee, "BLUE TOKAI COFFEE")
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-21")
    }

    func testParsesCreditAsCredit() {
        // Misreading a credit as spending would corrupt every downstream number.
        let text = "₹2,000 credited to your account XX1234 from RAHUL on 22Sep26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.direction, .credit)
        XCTAssertEqual(memo?.amountPaise, 200_000)
    }

    func testFallsBackToReceivedAtWhenAlertHasNoDate() {
        let text = "Rs 99.00 debited from a/c XX1234 to ZEPTO"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(PendingMemo.istDayString(memo!.date), "2026-09-22")
    }

    func testRejectsTextWithBothDirections() {
        // "credited"+"debited" in one message is a statement summary or an
        // ad, not a single movement. Guessing here is how you corrupt a ledger.
        let text = "Your a/c XX1234: Rs.500.00 debited and Rs.500.00 credited on 22-09-26"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testRejectsTextWithNoDirection() {
        let text = "Your a/c XX1234 balance is Rs.12,345.67 as on 22-09-26"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testRejectsTextWithNoCurrencyAmount() {
        // An account number must never be mistaken for an amount.
        let text = "Payment debited from a/c XX1234 to VEDANT"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testDoesNotMistakeEmailForVPA() {
        // An email has a dotted domain; a VPA handle does not.
        let text = "Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertNil(memo?.vpa)
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testRejectsPromotionalText() {
        // Rejected on direction: "Spend" is not "spent". Named for what it is.
        let text = "Get a personal loan instantly! Spend more and earn rewards."
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testDoesNotReadADottedDateAsAnAmount() {
        // The fallback two-decimal pattern would happily read "22.09" out of
        // "22.09.26" and report a ₹22.09 payment. A wrong number in the user's
        // own data is the one failure this product cannot absorb.
        let text = "Payment debited on 22.09.26 to ZEPTO"
        XCTAssertNil(AlertParser.parse(text: text, receivedAt: at(now)))
    }

    func testStillReadsAGenuineTwoDecimalAmountWithoutACurrencyMarker() {
        // The dotted-date guard must not swallow this.
        let text = "Debited 450.00 from a/c XX1234 to ZEPTO on 22-09-26"
        XCTAssertEqual(AlertParser.parse(text: text, receivedAt: at(now))?.amountPaise,
                       45_000)
    }
}
