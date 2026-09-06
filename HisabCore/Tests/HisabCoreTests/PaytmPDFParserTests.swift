import XCTest
@testable import HisabCore

final class PaytmPDFParserTests: XCTestCase {
    /// Page 1: summary block with signed totals BEFORE the table, then inline amounts.
    /// Page 2: header glued to the first date, all amounts trailing after the blocks.
    private let pages = [
        """
        Paytm Statement for
        5 MAR'26 - 4 SEP'26
        TEST USER
        ******2379, someone@example.com
        Total Money Received
        + Rs.600
        1 Payment received
        Total Money Paid
        - Rs.21,753.13
        38 Payments made
        Note:
        Self transfer payments are not included in the total money paid and money received calculations
        Accounts Payment received
        Payment made HDFC Bank - 93 Rs.13,053.13
        (37 Payments)
        Rs.0
        Passbook Payments History
        All payments done by you on Paytm App are reflected in this statement
        Date &
        Time
        Transaction Details Notes & Tags Your Account Amount
        02 Sep
        7:33 PM
        Paid to FirstClub
        UPI ID: firstclub-13003734.payu@indus
        UPI Ref No: 624536311139
        Note: UPIIntent
        Tag:
        # Groceries
        HDFC Bank -
        93
        - Rs.453
        15 Mar
        11:00 AM
        Received from A Friend
        UPI ID: friend@okhdfcbank
        UPI Ref No: 512345678901
        HDFC Bank -
        93
        + Rs.600
        """,
        """
        Passbook Payments History
        All payments done by you on Paytm App are reflected in this statement
        Date &
        Time
        Transaction Details Notes & Tags Your Account 24 Aug
        10:58 PM
        Paid to FirstClub
        UPI ID: cf.firstclub@cashfreensdlpb
        UPI Ref No: 623656756763
        Note: 6312806218
        Tag:
        # Groceries
        HDFC Bank -
        93
        22 Aug
        8:32 PM
        Paid to Some Long Merchant
        Name Wrapping
        UPI Ref No: 623456789012
        IDFC FIRST Bank -
        16
        - Rs.399
        - Rs.173.43
        Page of
        2 2
        For any queries,
        Contact Us
        """,
    ]

    func testParsesAllBlocksAcrossLayouts() throws {
        let doc = try PaytmPDFText.parse(pages: pages)
        XCTAssertEqual(doc.source, .paytm)
        XCTAssertEqual(doc.transactions.count, 4)
        XCTAssertEqual(doc.transactions.filter { $0.direction == .credit }.count, 1)
    }

    func testInlineAmountPage() throws {
        let txns = try PaytmPDFText.parse(pages: pages).transactions
        XCTAssertEqual(txns[0].counterparty, "FirstClub")
        XCTAssertEqual(txns[0].amountPaise, 45300)
        XCTAssertEqual(txns[0].reference, "624536311139")
        XCTAssertEqual(txns[1].counterparty, "A Friend")
        XCTAssertEqual(txns[1].direction, .credit)
        XCTAssertEqual(txns[1].amountPaise, 60000)
    }

    func testTrailingAmountsPairInOrder() throws {
        let txns = try PaytmPDFText.parse(pages: pages).transactions
        XCTAssertEqual(txns[2].amountPaise, 39900)      // 24 Aug block <- first trailing amount
        XCTAssertEqual(txns[2].reference, "623656756763")
        XCTAssertEqual(txns[3].amountPaise, 17343)      // 22 Aug block <- second trailing amount
        XCTAssertEqual(txns[3].counterparty, "Some Long Merchant Name Wrapping")
    }

    func testYearInferenceFromPeriod() throws {
        let txns = try PaytmPDFText.parse(pages: pages).transactions
        XCTAssertEqual(YearMonth(date: txns[0].date), YearMonth(year: 2026, month: 9))
        XCTAssertEqual(YearMonth(date: txns[1].date), YearMonth(year: 2026, month: 3))
        XCTAssertEqual(try PaytmPDFText.parse(pages: pages).declaredPeriod?.months.count, 7)
    }

    func testGluedHeaderDateDetected() throws {
        // The page-2 "…Your Account 24 Aug" line must start a block dated 24 Aug.
        let txns = try PaytmPDFText.parse(pages: pages).transactions
        XCTAssertEqual(YearMonth.istCalendar.component(.day, from: txns[2].date), 24)
    }

    func testBlockAmountCountMismatchThrows() {
        let broken = [pages[0].replacingOccurrences(of: "- Rs.453\n", with: "")]
        XCTAssertThrowsError(try PaytmPDFText.parse(pages: broken))
    }
}
