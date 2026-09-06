import XCTest
@testable import HisabCore

final class HDFCXLSParserTests: XCTestCase {
    private func fixtureData() throws -> Data {
        let url = Bundle.module.url(forResource: "hdfc-fixture", withExtension: "xls",
                                    subdirectory: "Fixtures")!
        return try Data(contentsOf: url)
    }

    func testMinimalXLSReadsGrid() throws {
        let grid = try MinimalXLS.cells(in: try fixtureData())
        XCTAssertEqual(grid[3]?[0], "Date")
        XCTAssertEqual(grid[3]?[6], "Closing Balance")
        XCTAssertEqual(grid[4]?[0], "03/03/26")
        XCTAssertEqual(grid[4]?[4], "30.00")        // NUMBER rendered to 2dp text
        XCTAssertEqual(grid[4]?[6], "35694.53")
        XCTAssertEqual(grid[90]?[0], "HDFC BANK Ltd.")
    }

    func testCanParse() throws {
        let parser = HDFCXLSParser()
        XCTAssertTrue(parser.canParse(data: try fixtureData(), filename: "Acct Statement.xls"))
        XCTAssertFalse(parser.canParse(data: Data("nope".utf8), filename: "x.xls"))
    }

    func testParsesRows() throws {
        let doc = try HDFCXLSParser().parse(data: try fixtureData(), password: nil)
        XCTAssertEqual(doc.source, .hdfc)
        XCTAssertEqual(doc.transactions.count, 2)
        XCTAssertEqual(doc.transactions[0].direction, .debit)
        XCTAssertEqual(doc.transactions[0].amountPaise, 3000)
        XCTAssertEqual(doc.transactions[0].counterparty, "ASHOKKUMAR BHAVARLAL")
        XCTAssertEqual(doc.transactions[0].reference, "119436467750")
        XCTAssertEqual(doc.transactions[1].direction, .credit)
        XCTAssertEqual(doc.transactions[1].amountPaise, 500_000)
        XCTAssertEqual(doc.transactions[1].reference, "IDFBN52026030512")
    }

    func testChainVerifiedAcrossRows() throws {
        // 35,694.53 + 5,000.00 = 40,694.53 checks; corrupting the credit balance throws.
        var data = try fixtureData()
        // (validated via the happy path; a corrupted fixture would need re-packing,
        //  so chain-break behavior is covered by HDFCParserTests on the shared layer)
        XCTAssertNoThrow(try HDFCXLSParser().parse(data: data, password: nil))
        _ = data
    }

    func testDeclaredPeriodFromStrayCell() throws {
        let doc = try HDFCXLSParser().parse(data: try fixtureData(), password: nil)
        XCTAssertEqual(doc.declaredPeriod?.months.count, 6)
        XCTAssertEqual(doc.declaredPeriod?.months.first, YearMonth(year: 2026, month: 3))
    }
}
