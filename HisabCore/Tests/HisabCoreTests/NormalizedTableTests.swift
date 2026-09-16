import XCTest
@testable import HisabCore

final class NormalizedTableTests: XCTestCase {
    func testCSVSplitsRowsAndTrims() {
        let csv = "Date,Narration,Debit,Credit,Balance\n01/04/2026, UPI/1/x ,100.00,,900.00\n"
        let t = NormalizedTable.from(data: Data(csv.utf8), filename: "a.csv", password: nil)
        XCTAssertEqual(t?.container, "csv")
        XCTAssertEqual(t?.rows[1], ["01/04/2026", "UPI/1/x", "100.00", "", "900.00"])
    }

    func testCSVRespectsQuotedCommas() {
        let csv = "Date,Narration,Balance\n01/04/2026,\"POS, COFFEE\",900.00\n"
        let t = NormalizedTable.from(data: Data(csv.utf8), filename: "a.csv", password: nil)
        XCTAssertEqual(t?.rows[1], ["01/04/2026", "POS, COFFEE", "900.00"])
    }

    func testTXTSplitsOnRunsOfSpaces() {
        let txt = "Date         Narration            Amount     Balance\n01/04/26     POS COFFEE           100.00     900.00\n"
        let t = NormalizedTable.from(data: Data(txt.utf8), filename: "a.txt", password: nil)
        XCTAssertEqual(t?.container, "txt")
        XCTAssertEqual(t?.rows[1], ["01/04/26", "POS COFFEE", "100.00", "900.00"])
    }

    func testXLSXFixtureProducesRows() throws {
        let url = Bundle.module.url(forResource: "paytm-fixture", withExtension: "xlsx",
                                    subdirectory: "Fixtures")!
        let t = NormalizedTable.from(data: try Data(contentsOf: url), filename: "s.xlsx", password: nil)
        XCTAssertEqual(t?.container, "xlsx")
        XCTAssertGreaterThan(t!.rows.count, 3)
    }

    func testXLSFixtureProducesRows() throws {
        let url = Bundle.module.url(forResource: "hdfc-fixture", withExtension: "xls",
                                    subdirectory: "Fixtures")!
        let t = NormalizedTable.from(data: try Data(contentsOf: url), filename: "s.xls", password: nil)
        XCTAssertEqual(t?.container, "xls")
        XCTAssertGreaterThan(t!.rows.count, 3)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(NormalizedTable.from(data: Data([0x00, 0x01, 0x02]), filename: "a.xlsx", password: nil))
    }
}
