import XCTest
@testable import HisabCore

final class GPayParserTests: XCTestCase {
    /// Mirrors the exact line structure PDFKit extracts from a real GPay statement,
    /// including page headers/footers, summary block, and a wrapped merchant name.
    private let fixture = """
    Transaction statement
    6374482379,
    someone@example.com
    Transaction statement period
    01 March 2026 - 31 August 2026
    Sent
    ₹3,47,622.60
    Received
    ₹23,205
    Date & time Transaction details Amount
    03 Mar, 2026
    01:09 PM
    Paid to ASHOKKUMAR BHAVARLAL NAGLA
    UPI Transaction ID: 119436467750
    Paid by HDFC Bank 3293
    ₹30
    05 Mar, 2026
    02:56 PM
    Paid to Akshat vijayvargia
    UPI Transaction ID: 606435614627
    Paid by IDFC FIRST Bank 8816
    ₹24,572
    Note: This statement reflects payments made by you on the Google Pay app. Self transfer payments are not included in the total money paid and
    received. Any payments transactions and activity deleted from your Google Account will not show up in this statement.
    Page 1 of 2
    Transaction statement
    6374482379,
    someone@example.com
    Date & time Transaction details Amount
    12 Mar, 2026
    09:30 AM
    Received from Google Cloud
    UPI Transaction ID: 725798230736
    Paid to HDFC Bank 3293
    ₹2
    14 Jul, 2026
    11:59 PM
    Paid to Some Very Long Merchant
    Name That Wraps Lines
    UPI Transaction ID: 999888777666
    Paid by HDFC Bank 3293
    ₹1,234.56
    Page 2 of 2
    """

    func testParsesAllBlocks() throws {
        let doc = try GPayStatementText.parse(fixture)
        XCTAssertEqual(doc.source, .gpay)
        XCTAssertEqual(doc.transactions.count, 4)
    }

    func testDeclaredPeriodFromHeader() throws {
        let doc = try GPayStatementText.parse(fixture)
        XCTAssertEqual(doc.declaredPeriod?.months.count, 6)
        XCTAssertEqual(doc.declaredPeriod?.months.first, YearMonth(year: 2026, month: 3))
        XCTAssertEqual(doc.declaredPeriod?.months.last, YearMonth(year: 2026, month: 8))
    }

    func testDebitBlock() throws {
        let txn = try GPayStatementText.parse(fixture).transactions[0]
        XCTAssertEqual(txn.direction, .debit)
        XCTAssertEqual(txn.counterparty, "ASHOKKUMAR BHAVARLAL NAGLA")
        XCTAssertEqual(txn.reference, "119436467750")
        XCTAssertEqual(txn.amountPaise, 3000)
        XCTAssertEqual(YearMonth(date: txn.date), YearMonth(year: 2026, month: 3))
        XCTAssertTrue(txn.narration.contains("Paid by HDFC Bank 3293"))
    }

    func testIndianGroupedAmount() throws {
        let txn = try GPayStatementText.parse(fixture).transactions[1]
        XCTAssertEqual(txn.amountPaise, 2_457_200)
    }

    func testCreditBlock() throws {
        let txn = try GPayStatementText.parse(fixture).transactions[2]
        XCTAssertEqual(txn.direction, .credit)
        XCTAssertEqual(txn.counterparty, "Google Cloud")
        XCTAssertEqual(txn.amountPaise, 200)
    }

    func testWrappedMerchantNameAndDecimals() throws {
        let txn = try GPayStatementText.parse(fixture).transactions[3]
        XCTAssertEqual(txn.counterparty, "Some Very Long Merchant Name That Wraps Lines")
        XCTAssertEqual(txn.amountPaise, 123_456)
    }

    func testAmountParsing() {
        XCTAssertEqual(GPayStatementText.paise(fromRupeeString: "₹30"), 3000)
        XCTAssertEqual(GPayStatementText.paise(fromRupeeString: "₹3,47,622.60"), 34_762_260)
        XCTAssertEqual(GPayStatementText.paise(fromRupeeString: "₹23,205"), 2_320_500)
        XCTAssertEqual(GPayStatementText.paise(fromRupeeString: "₹1,234.5"), 123_450)
        XCTAssertNil(GPayStatementText.paise(fromRupeeString: "garbage"))
    }

    func testTruncatedBlockThrows() {
        let bad = """
        Transaction statement period
        01 March 2026 - 31 August 2026
        03 Mar, 2026
        01:09 PM
        Paid to Someone
        UPI Transaction ID: 12345
        """
        XCTAssertThrowsError(try GPayStatementText.parse(bad))
    }

    func testNoTransactionsThrowsEmpty() {
        XCTAssertThrowsError(try GPayStatementText.parse("Transaction statement period\n01 March 2026 - 31 August 2026")) {
            XCTAssertEqual($0 as? ParseError, .empty)
        }
    }
}
