import XCTest
@testable import HisabCore

final class HDFCTXTParserTests: XCTestCase {
    private let fixture = """


    HDFC BANK Ltd.                                     Page No .:   1                                        Statement of accounts

    Statement From      : 01/03/2026  To: 31/08/2026                         RTGS/NEFT IFSC : HDFC0000257    MICR : 444240101

    Date      Narration\t\t\t\t    Chq./Ref.No.      Value Dt  Withdrawal Amt.        Deposit Amt.     Closing Balance
    --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------

    03/03/26  UPI-ASHOKKUMAR BHAVARLAL-BHARATPE.9M0U0S  0000119436467750  03/03/26              30.00                              35,694.53
              0E4W332902@UNITYPE-UNBA000BHPE-119436467
              750-PAY TO BHARATPE ME
    05/03/26  NEFT CR-IDFB0042503-VEDANT ASHISH SABOO-  IDFBN52026030512  05/03/26                              5,000.00           40,694.53
              TRANSFER FROM IDFC
    31/03/26  INTEREST PAID TILL 31-MAR-2026            000000000000000   31/03/26                                 60.00           40,754.53
    HDFC BANK Ltd.                                     Page No .:   2                                        Statement of accounts
    Date      Narration\t\t\t\t    Chq./Ref.No.      Value Dt  Withdrawal Amt.        Deposit Amt.     Closing Balance
    --------  ----------------------------------------  ----------------  --------  ------------------  ------------------  ------------------
    02/04/26  UPI-SWIGGY LIMITED-SWIGGY1ONLINE.GPAY@OK  0000103000000009  02/04/26             436.00                              40,318.53
              PAYAXIS-UTIB0000553-103000000009-UPI

             STATEMENT SUMMARY  :-
               Opening Balance                                                      Debits              Credits          Closing Bal
                     35,724.53                                                     466.00             5,060.00            40,318.53

                                                                              Dr Count             Cr Count
                                                                                     2                    2

    """

    func testParsesRowsWithContinuations() throws {
        let doc = try HDFCTXTParser().parse(data: Data(fixture.utf8), password: nil)
        XCTAssertEqual(doc.source, .hdfc)
        XCTAssertEqual(doc.transactions.count, 4)
        XCTAssertEqual(doc.transactions.map(\.direction), [.debit, .credit, .credit, .debit])
        XCTAssertEqual(doc.transactions[0].amountPaise, 3000)
        XCTAssertTrue(doc.transactions[0].narration.contains("PAY TO BHARATPE ME"))
        XCTAssertEqual(doc.transactions[0].counterparty, "ASHOKKUMAR BHAVARLAL")
        XCTAssertEqual(doc.transactions[0].reference, "119436467750")
    }

    func testChainSeededFromSummaryOpeningBalance() throws {
        // 35,724.53 - 30 = 35,694.53 must validate; a corrupted balance must throw.
        let broken = fixture.replacingOccurrences(of: "35,694.53", with: "35,000.00")
        XCTAssertThrowsError(try HDFCTXTParser().parse(data: Data(broken.utf8), password: nil))
    }

    func testAlphanumericNEFTRefKept() throws {
        let doc = try HDFCTXTParser().parse(data: Data(fixture.utf8), password: nil)
        XCTAssertEqual(doc.transactions[1].reference, "IDFBN52026030512")
        XCTAssertEqual(doc.transactions[1].counterparty, "VEDANT ASHISH SABOO")
    }

    func testDeclaredPeriod() throws {
        let doc = try HDFCTXTParser().parse(data: Data(fixture.utf8), password: nil)
        XCTAssertEqual(doc.declaredPeriod?.months.count, 6)
        XCTAssertEqual(doc.declaredPeriod?.months.first, YearMonth(year: 2026, month: 3))
    }

    func testCanParse() {
        XCTAssertTrue(HDFCTXTParser().canParse(data: Data(fixture.utf8), filename: "Acct Statement_3293.txt"))
        XCTAssertFalse(HDFCTXTParser().canParse(data: Data("random".utf8), filename: "x.txt"))
    }
}
