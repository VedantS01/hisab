import XCTest
@testable import HisabCore

final class PaytmParserTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = Bundle.module.url(forResource: "paytm-fixture", withExtension: "xlsx",
                                    subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testZipExtractsSheets() throws {
        let entries = try MinimalZip.entries(in: try fixtureData())
        XCTAssertNotNil(entries["xl/sharedStrings.xml"])
        XCTAssertNotNil(entries["xl/worksheets/sheet2.xml"])
        let ss = String(data: entries["xl/sharedStrings.xml"]!, encoding: .utf8)!
        XCTAssertTrue(ss.contains("Paytm Statement for"))
    }

    func testCanParse() throws {
        let parser = PaytmXLSXParser()
        XCTAssertTrue(parser.canParse(data: try fixtureData(), filename: "Paytm_UPI_Statement.xlsx"))
        XCTAssertFalse(parser.canParse(data: Data("nope".utf8), filename: "x.xlsx"))
    }

    func testParsesAllRows() throws {
        let doc = try PaytmXLSXParser().parse(data: try fixtureData(), password: nil)
        XCTAssertEqual(doc.source, .paytm)
        XCTAssertEqual(doc.transactions.count, 4)
        XCTAssertEqual(doc.transactions.filter { $0.direction == .debit }.count, 3)
        XCTAssertEqual(doc.transactions.filter { $0.direction == .credit }.count, 1)
    }

    func testDeclaredPeriodFromSummary() throws {
        let doc = try PaytmXLSXParser().parse(data: try fixtureData(), password: nil)
        XCTAssertEqual(doc.declaredPeriod?.months.first, YearMonth(year: 2026, month: 3))
        XCTAssertEqual(doc.declaredPeriod?.months.last, YearMonth(year: 2026, month: 9))
        XCTAssertEqual(doc.declaredPeriod?.months.count, 7)
    }

    func testDebitRow() throws {
        let txn = try PaytmXLSXParser().parse(data: try fixtureData(), password: nil).transactions[0]
        XCTAssertEqual(txn.direction, .debit)
        XCTAssertEqual(txn.amountPaise, 45300)
        XCTAssertEqual(txn.counterparty, "FirstClub")
        XCTAssertEqual(txn.reference, "624536311139")
        XCTAssertEqual(YearMonth(date: txn.date), YearMonth(year: 2026, month: 9))
        XCTAssertTrue(txn.narration.contains("HDFC Bank - 93"))
    }

    func testNonPaidToDetailKeptVerbatim() throws {
        let txn = try PaytmXLSXParser().parse(data: try fixtureData(), password: nil).transactions[2]
        XCTAssertEqual(txn.counterparty, "Automatic payment of ₹99 setup for Apple Media Services")
        XCTAssertEqual(txn.amountPaise, 9900)
    }

    func testCreditRow() throws {
        let txn = try PaytmXLSXParser().parse(data: try fixtureData(), password: nil).transactions[3]
        XCTAssertEqual(txn.direction, .credit)
        XCTAssertEqual(txn.counterparty, "A Friend")
        XCTAssertEqual(txn.amountPaise, 60000)
    }
}
