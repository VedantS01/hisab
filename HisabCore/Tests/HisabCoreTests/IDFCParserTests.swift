import XCTest
@testable import HisabCore

final class IDFCParserTests: XCTestCase {
    /// Mirrors PDFKit extraction of a real IDFC statement: merged date+particulars
    /// lines, multi-line particulars, a row spanning a page break with page furniture
    /// inside it, and direction only recoverable from the running balance.
    private let pages = [
        """
        STATEMENT OF ACCOUNT
        CUSTOMER ID : 55******29
        ACCOUNT NO : 10061308816
        STATEMENT PERIOD : 2026-03-01 TO 2026-08-31
        CUSTOMER NAME : Mr. Test User
        Opening Balance Total Debit Total Credit Closing Balance
        11,16,221.76 16,37,345.99 24,56,605.55 19,35,481.32
        Transaction
        Date Value Date Particulars Cheque
        No Debit Credit Balance
        Opening Balance 11,16,221.76
        02-Mar-2026 02-Mar-2026
        NEFT/
        HDFCH00834165953/
        INFURNIA
        TECHNOLOGIES
        PRIVATE LIMIT/
        HDFC0000240/
        3,03,594.00 14,19,815.76
        04-Mar-2026 04-Mar-2026 POS-VISA/
        Mcafee/606205789898/560103/05:28:43 1,999.00 14,17,816.76
        05-Mar-2026 05-Mar-2026 UPI/DR/606435614627/
        Akshat V/IDFB/avijayv/UPI 24,572.00 13,93,244.76
        21-Mar-2026 21-Mar-2026
        UPI/CR/644698405234/
        Vinayak /SBIN/vinayak/
        UPI
        1,000.00 13,94,244.76
        30-Mar-2026 30-Mar-2026
        NACH/NSEMFS
        REGISTERED OFFICE: IDFC FIRST BANK LIMITED, KRM Tower.
        Page 1 of 2
        """,
        """
        STATEMENT OF ACCOUNT
        CUSTOMER ID : 55******29
        ACCOUNT NO : 10061308816
        STATEMENT PERIOD : 2026-03-01 TO 2026-08-31
        Opening Balance Total Debit Total Credit Closing Balance
        11,16,221.76 16,37,345.99 24,56,605.55 19,35,481.32
        Transaction
        Date Value Date Particulars Cheque
        No Debit Credit Balance
        05032026/5950864403002
        5,000.00 13,89,244.76
        REGISTERED OFFICE: IDFC FIRST BANK LIMITED, KRM Tower.
        Page 2 of 2
        """,
    ]

    func testParsesAllRowsIncludingPageSpanning() throws {
        let doc = try IDFCStatementText.parse(pages: pages)
        XCTAssertEqual(doc.source, .idfc)
        XCTAssertEqual(doc.transactions.count, 5)
    }

    func testDeclaredPeriodFromHeader() throws {
        let doc = try IDFCStatementText.parse(pages: pages)
        XCTAssertEqual(doc.declaredPeriod?.months.count, 6)
        XCTAssertEqual(doc.declaredPeriod?.months.first, YearMonth(year: 2026, month: 3))
    }

    func testDirectionsFromBalanceChain() throws {
        let txns = try IDFCStatementText.parse(pages: pages).transactions
        XCTAssertEqual(txns.map(\.direction), [.credit, .debit, .debit, .credit, .debit])
        XCTAssertEqual(txns[0].amountPaise, 30_359_400)
        XCTAssertEqual(txns[4].amountPaise, 500_000)
    }

    func testNEFTExtraction() throws {
        let txn = try IDFCStatementText.parse(pages: pages).transactions[0]
        XCTAssertEqual(txn.reference, "HDFCH00834165953")
        XCTAssertEqual(txn.counterparty, "INFURNIA TECHNOLOGIES PRIVATE LIMIT")
    }

    func testPOSExtraction() throws {
        let txn = try IDFCStatementText.parse(pages: pages).transactions[1]
        XCTAssertEqual(txn.counterparty, "Mcafee")
        XCTAssertEqual(txn.reference, "606205789898")
    }

    func testUPIExtraction() throws {
        let txns = try IDFCStatementText.parse(pages: pages).transactions
        XCTAssertEqual(txns[2].reference, "606435614627")
        XCTAssertEqual(txns[2].counterparty, "Akshat V")
        XCTAssertEqual(txns[3].reference, "644698405234")
        XCTAssertEqual(txns[3].counterparty, "Vinayak")
    }

    func testGenericRowKeepsParticularsAsCounterparty() throws {
        let txn = try IDFCStatementText.parse(pages: pages).transactions[4]
        XCTAssertNil(txn.reference)
        XCTAssertTrue(txn.counterparty.hasPrefix("NACH/NSEMFS"))
    }

    func testBrokenBalanceChainThrows() {
        let broken = [pages[0].replacingOccurrences(of: "13,93,244.76", with: "13,93,000.00")]
        XCTAssertThrowsError(try IDFCStatementText.parse(pages: broken))
    }
}
