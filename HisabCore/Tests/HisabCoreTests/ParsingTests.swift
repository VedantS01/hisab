import XCTest
@testable import HisabCore

final class ParsingTests: XCTestCase {
    private let happy = """
    hisab-demo-csv,v1
    period,2026-09-01,2026-09-30
    2026-09-02,25000,debit,Swiggy,UPI111,SWIGGY ORDER
    2026-09-15,500000,credit,Acme Corp,NEFT99,SALARY PART
    """

    private let noPeriod = """
    hisab-demo-csv,v1
    2026-09-02,25000,debit,Swiggy,,SWIGGY ORDER
    2026-10-01,10000,debit,Zomato,,ZOMATO ORDER
    """

    func testRegistryDetection() {
        let registry = ParserRegistry.live
        XCTAssertNotNil(registry.detect(data: Data(happy.utf8), filename: "demo.csv"))
        XCTAssertNil(registry.detect(data: Data("random,stuff".utf8), filename: "x.csv"))
    }

    func testHappyPathParse() throws {
        let doc = try SyntheticCSVParser().parse(data: Data(happy.utf8), password: nil)
        XCTAssertEqual(doc.source, .gpay)
        XCTAssertEqual(doc.transactions.count, 2)
        XCTAssertEqual(doc.transactions[0].amountPaise, 25000)
        XCTAssertEqual(doc.transactions[0].reference, "UPI111")
        XCTAssertEqual(doc.transactions[1].direction, .credit)
        XCTAssertEqual(doc.declaredPeriod?.months, [YearMonth(year: 2026, month: 9)])
    }

    func testEffectivePeriodFallsBackToTxnDates() throws {
        let doc = try SyntheticCSVParser().parse(data: Data(noPeriod.utf8), password: nil)
        XCTAssertNil(doc.declaredPeriod)
        XCTAssertEqual(doc.effectivePeriod.months,
                       [YearMonth(year: 2026, month: 9), YearMonth(year: 2026, month: 10)])
    }

    func testEmptyReferenceBecomesNil() throws {
        let doc = try SyntheticCSVParser().parse(data: Data(noPeriod.utf8), password: nil)
        XCTAssertNil(doc.transactions[0].reference)
    }

    func testMalformedRowCarriesLineNumber() {
        let bad = "hisab-demo-csv,v1\nnot-a-date,25000,debit,X,,Y"
        XCTAssertThrowsError(try SyntheticCSVParser().parse(data: Data(bad.utf8), password: nil)) { error in
            XCTAssertEqual(error as? ParseError, .malformedRow(2, "not-a-date,25000,debit,X,,Y"))
        }
    }

    func testHeaderOnlyIsEmpty() {
        XCTAssertThrowsError(try SyntheticCSVParser().parse(data: Data("hisab-demo-csv,v1".utf8), password: nil)) { error in
            XCTAssertEqual(error as? ParseError, .empty)
        }
    }
}
