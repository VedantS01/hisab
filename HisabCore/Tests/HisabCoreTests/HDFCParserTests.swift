import XCTest
@testable import HisabCore

final class HDFCParserTests: XCTestCase {
    private func row(date: String? = nil, narr: String = "", ref: String? = nil,
                     w: String? = nil, d: String? = nil, bal: String? = nil) -> HDFCRow {
        HDFCRow(dateText: date, narration: narr, refText: ref,
                withdrawalText: w, depositText: d, balanceText: bal)
    }

    private var happyRows: [HDFCRow] {
        [
            row(date: "01/04/25", narr: "UPI-SAHUL HAMEED-Q249795806@YBL-YESB0YBL UPI-102422789385-UPI",
                ref: "0000102422789385", w: "14.00", bal: "10,041.58"),
            row(date: "02/04/25", narr: "UPI-SWIGGY LIMITED-SWIGGY1ONLINE.GPAY@OKPAYAXIS-UTIB0000553-102448862938-UPI",
                ref: "0000102448862938", w: "436.00", bal: "9,605.58"),
            row(date: "01/05/25", narr: "NEFT CR-HDFC0000240-INFURNIA TECHNOLOGIES-SALARY",
                ref: "0000103000000001", d: "50,000.00", bal: "59,605.58"),
            row(date: "31/03/26", narr: "INTEREST PAID TILL 31-MAR-2026",
                ref: "000000000000000", d: "60.00", bal: "59,665.58"),
        ]
    }

    func testParsesRows() throws {
        let doc = try HDFCStatementTable.parse(rows: happyRows, openingBalancePaise: 1_005_558,
                                               period: nil)
        XCTAssertEqual(doc.source, .hdfc)
        XCTAssertEqual(doc.transactions.count, 4)
        XCTAssertEqual(doc.transactions.map(\.direction), [.debit, .debit, .credit, .credit])
        XCTAssertEqual(doc.transactions[0].amountPaise, 1400)
        XCTAssertEqual(doc.transactions[2].amountPaise, 5_000_000)
    }

    func testUPICounterpartyAndNormalizedRef() throws {
        let doc = try HDFCStatementTable.parse(rows: happyRows, openingBalancePaise: 1_005_558, period: nil)
        XCTAssertEqual(doc.transactions[0].counterparty, "SAHUL HAMEED")
        XCTAssertEqual(doc.transactions[0].reference, "102422789385")  // leading zeros stripped
        XCTAssertEqual(doc.transactions[1].counterparty, "SWIGGY LIMITED")
    }

    func testAllZeroRefGetsSyntheticBalanceIdentity() throws {
        let doc = try HDFCStatementTable.parse(rows: happyRows, openingBalancePaise: 1_005_558, period: nil)
        let interest = doc.transactions[3]
        XCTAssertEqual(interest.reference, "B5966558D20260331A6000")
        XCTAssertEqual(interest.counterparty, "INTEREST PAID TILL 31-MAR-2026")
    }

    func testBalanceChainBreakThrows() {
        var rows = happyRows
        rows[1].balanceText = "9,999.99"
        XCTAssertThrowsError(try HDFCStatementTable.parse(rows: rows, openingBalancePaise: 1_005_558, period: nil))
    }

    func testBothAmountColumnsThrows() {
        var rows = happyRows
        rows[0].depositText = "1.00"
        XCTAssertThrowsError(try HDFCStatementTable.parse(rows: rows, openingBalancePaise: 1_005_558, period: nil))
    }

    func testEffectivePeriodFromRowsWhenNoDeclared() throws {
        let doc = try HDFCStatementTable.parse(rows: happyRows, openingBalancePaise: 1_005_558, period: nil)
        XCTAssertEqual(doc.effectivePeriod.months.first, YearMonth(year: 2025, month: 4))
        XCTAssertEqual(doc.effectivePeriod.months.last, YearMonth(year: 2026, month: 3))
    }
}
