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
        XCTAssertEqual(memo?.payee, "vedant@okaxis")
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
        // C2: the payee must be the sender, never the masked-account boilerplate.
        XCTAssertEqual(memo?.payee, "RAHUL")
    }

    func testFallsBackToReceivedAtWhenAlertHasNoDate() {
        let text = "Rs 99.00 debited from a/c XX1234 to ZEPTO"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "ZEPTO")
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
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.amountPaise, 45_000)
        XCTAssertEqual(memo?.payee, "ZEPTO")
    }

    func testReadsVPAWhenTheAlertEndsTheSentenceWithAPeriod() {
        // Regression: a trailing sentence period must not be mistaken for a
        // dotted email domain and swallow the VPA.
        let text = "Rs.100.00 debited from a/c XX1234 to VPA vedant@okaxis. Thank you for using UPI."
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.vpa, "vedant@okaxis")
        XCTAssertEqual(memo?.payee, "vedant@okaxis")
    }

    func testDoesNotReadAnEmailAsAVPAEvenAtTheEndOfASentence() {
        // An email domain dot must still block a VPA match, even when a
        // second, sentence-ending period follows immediately after it.
        let text = "Rs.450.00 debited from a/c XX1234 to SWIGGY. Queries: help@swiggy.in."
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertNil(memo?.vpa)
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testDoesNotTruncateAMerchantNameContainingAStopWord() {
        // C1: " bal" (intended for "Avl Bal" boilerplate) must not fire as a
        // substring inside "BALAJI" — stop words are tokens, not substrings.
        let text = "Rs.200.00 debited from a/c XX1234 to SRI BALAJI STORES on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SRI BALAJI STORES")
    }

    func testIgnoresALeadingDisclaimerWhenFindingThePayee() {
        // C3: the lead-in search must anchor after the direction keyword, or
        // a leading disclaimer's " to " hijacks the match.
        let text = "For queries write to us at 1800123456. Rs.500.00 debited from a/c XX1234 to SWIGGY on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testReadsANumericVPA() {
        let text = "Rs.150.00 debited from a/c XX1234 to VPA 9876543210@ybl on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.vpa, "9876543210@ybl")
        XCTAssertEqual(memo?.payee, "9876543210@ybl")
    }

    func testIgnoresABoilerplatePreambleContainingADirectionWord() {
        // N1: direction words ("sent") routinely appear in template preambles.
        // Anchoring on the amount instead of the direction word means the
        // preamble, and the disclaimer's " to ", cannot hijack the match.
        let text = "This SMS is sent by XYZ Bank. For queries write to us at 1800123456. Rs.500.00 debited from a/c XX1234 to SWIGGY on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testKeepsAMerchantNameContainingOnAsAWord() {
        // N2: "on" only ends a payee when a date plausibly follows it, so
        // "X ON WHEELS" (a real Indian business pattern) survives intact.
        let text = "Rs.150.00 debited from a/c XX1234 to SHOP ON WHEELS on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SHOP ON WHEELS")
    }

    func testKeepsAMerchantNameStartingWithAFormerStopWord() {
        // N3: a name whose first token used to be a stop token ("id") must
        // not be dropped entirely.
        let text = "Rs.320.00 debited from a/c XX1234 to ID FRESH FOOD on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "ID FRESH FOOD")
    }

    func testStopsAtAConnectorWord() {
        // N4: connector words like "using" must not leak into the payee and
        // fragment one merchant into two different rule keys.
        let text = "Purchase of Rs.450.00 at SWIGGY using a/c XX1234"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SWIGGY")
    }

    func testStopsAtViaInAPaidAlert() {
        // "via UPI" is one of the commonest tails in Indian payment alerts;
        // round 3 briefly let it leak into the payee as "SWIGGY via".
        let text = "You have paid Rs.450.00 to SWIGGY via UPI on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "SWIGGY")
        XCTAssertEqual(memo?.direction, .debit)
        XCTAssertEqual(memo?.amountPaise, 45_000)
    }

    func testPayeeSurvivesCharactersThatLengthenWhenLowercased() {
        // I-3: `lowercased()` can make a string LONGER — U+0130 "İ" becomes
        // "i" + U+0307 — so a `String.Index` taken from the lowercased mirror
        // is not a valid index into the original. Slicing the original with
        // one used to trap ("Range requires lowerBound <= upperBound") once
        // the run was long enough. The App Intent takes arbitrary user text
        // from Shortcuts, the share sheet and Siri, so this is reachable.
        let padding = String(repeating: "\u{0130}", count: 20)
        let text = "Rs.450.00 debited \(padding) to ZEPTO"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "ZEPTO")
        XCTAssertEqual(memo?.amountPaise, 45_000)
    }

    func testAShortLowercaseLengtheningRunDoesNotShiftThePayee() {
        // The same defect below the trapping threshold: a single U+0130 slid
        // the slice one byte along and returned a mangled payee instead.
        let text = "Rs.450.00 debited \u{0130} to ZEPTO CORNER on 22-09-26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo?.payee, "ZEPTO CORNER")
    }

    func testAnUnreadableNumericDateFallsThroughToTheNamedMonth() {
        // I-2: the numeric pattern matches "12-34-56" inside a reference
        // number, and month 34 is not a month. That dead candidate must not
        // veto the real "20Sep26" later in the same alert — the memo's date
        // feeds `captureHash`, so vetoing it gave the two cores different
        // identities for one alert and shifted MemoMerger's ±3-day window.
        let text = "Rs.100 debited to Cafe Mocha ref 12-34-5678 on 20Sep26"
        let memo = AlertParser.parse(text: text, receivedAt: at(now))
        XCTAssertEqual(memo.map { PendingMemo.istDayString($0.date) }, "2026-09-20")
        XCTAssertEqual(memo?.payee, "Cafe Mocha")
    }
}
