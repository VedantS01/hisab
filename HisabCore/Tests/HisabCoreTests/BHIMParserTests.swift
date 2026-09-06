import XCTest
@testable import HisabCore

final class BHIMParserTests: XCTestCase {
    private let fixture = """
    Transaction History
    Customer Mobile Number: +916374482379
    Transaction History from 06/08/2026 to 06/09/2026
    Date Time Bank Name Account Number Sender Receiver Payment ID/Reference Number Pay/Collect Amount (in Rs.) DR/CR Status
    06/09/2026 11:52:01 HDFC BANK LTD XXXXXXXXXX3293 xxxxxxxhback@hdfcbank(NPCI BHIM) xxxxx82379@upi(xxxxxxxxABOO) 104000969489 PAY 20.00 CR SUCCESS
    06/09/2026 11:51:59 HDFC BANK LTD XXXXXXXXXX3293 xxxxx82379@upi(VEDANT ASHISH SABOO) xxxxgyupi@axb(Swiggy Ltd) 115159963311 PAY 219.00 DR SUCCESS
    05/09/2026 10:00:00 HDFC BANK LTD XXXXXXXXXX3293 xxxxx82379@upi(VEDANT ASHISH SABOO) someone@upi(Nobody) 999999999999 PAY 500.00 DR FAILURE
    """

    func testSourceRegistration() {
        XCTAssertEqual(Source.bhim.kind, .paymentApp)
        XCTAssertTrue(Source.allCases.contains(.bhim))
    }

    func testParsesSuccessRowsOnly() throws {
        let doc = try BHIMStatementText.parse(text: fixture)
        XCTAssertEqual(doc.source, .bhim)
        XCTAssertEqual(doc.transactions.count, 2)  // FAILURE row skipped
    }

    func testCreditRow() throws {
        let txn = try BHIMStatementText.parse(text: fixture).transactions[0]
        XCTAssertEqual(txn.direction, .credit)
        XCTAssertEqual(txn.amountPaise, 2000)
        XCTAssertEqual(txn.counterparty, "NPCI BHIM")   // sender's name for credits
        XCTAssertEqual(txn.reference, "104000969489")
    }

    func testDebitRow() throws {
        let txn = try BHIMStatementText.parse(text: fixture).transactions[1]
        XCTAssertEqual(txn.direction, .debit)
        XCTAssertEqual(txn.amountPaise, 21900)
        XCTAssertEqual(txn.counterparty, "Swiggy Ltd")  // receiver's name for debits
        XCTAssertEqual(txn.reference, "115159963311")
    }

    func testDeclaredPeriod() throws {
        let doc = try BHIMStatementText.parse(text: fixture)
        XCTAssertEqual(doc.declaredPeriod?.months.map(\.description), ["2026-08", "2026-09"])
    }

    func testNoRowsThrowsEmpty() {
        XCTAssertThrowsError(try BHIMStatementText.parse(text: "Transaction History from 06/08/2026 to 06/09/2026")) {
            XCTAssertEqual($0 as? ParseError, .empty)
        }
    }
}
