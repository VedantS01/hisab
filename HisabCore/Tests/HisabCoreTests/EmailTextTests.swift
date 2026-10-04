import XCTest
@testable import HisabCore

final class EmailTextTests: XCTestCase {
    private let email = """
        <html><head><style>p { color: #333; font-family: Arial; }</style></head>
        <body><!-- tracking --><table><tr><td>
        <p>Dear Customer,</p>
        <p>Rs.450.00 has been debited from account **1234 to VPA vedant@okaxis on 22-09-26.</p>
        <p>Your UPI transaction reference number is&nbsp;627775786529.</p>
        <p>Not you? Call us &amp; block UPI &#8377; &#x20B9; &amp;lt;</p>
        </td></tr></table></body></html>
        """

    func testSMSPassesThroughUntouched() {
        let sms = "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. UPI Ref No 627775786529 <limit 5000>"
        XCTAssertEqual(EmailText.plain(sms), sms)
    }

    func testHTMLEmailBecomesItsVisibleText() {
        XCTAssertEqual(EmailText.plain(email),
                       "Dear Customer, Rs.450.00 has been debited from account **1234 to VPA vedant@okaxis on 22-09-26. "
                       + "Your UPI transaction reference number is 627775786529. Not you? Call us & block UPI ₹ ₹ &lt;")
    }

    func testExtractorReadsTheStrippedEmail() throws {
        let alert = try AlertExtractor.live().extract(EmailText.plain(email))
        XCTAssertTrue(alert.isTransaction)
        XCTAssertEqual(alert.direction, .debit)
        XCTAssertEqual(alert.amountPaise, 45_000)
        XCTAssertEqual(alert.ref, "627775786529")
    }
}
