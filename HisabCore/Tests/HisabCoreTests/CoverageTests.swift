import XCTest
@testable import HisabCore

final class CoverageTests: XCTestCase {
    private func istDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        YearMonth.istCalendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func doc(_ source: Source, _ sy: Int, _ sm: Int, _ ey: Int, _ em: Int, id: UUID = UUID()) -> DocumentSummary {
        DocumentSummary(id: id, source: source,
                        period: DatePeriod(start: istDate(sy, sm, 1), end: istDate(ey, em, 28)))
    }

    func testYearlyDocLightsTwelveCellsInItsColumnOnly() {
        let grid = CoverageGrid.derive(documents: [doc(.hdfc, 2025, 4, 2026, 3)], pinnedMonths: [])
        XCTAssertEqual(grid.months.count, 12)
        XCTAssertEqual(grid.months.first, YearMonth(year: 2026, month: 3), "newest first")
        for month in grid.months {
            if case .awaiting = grid.state(month: month, source: .hdfc) { XCTFail("hdfc should be present for \(month)") }
            guard case .awaiting = grid.state(month: month, source: .gpay) else { return XCTFail("gpay should be awaiting") }
        }
    }

    func testPresentCellCarriesDocumentIDs() {
        let id = UUID()
        let grid = CoverageGrid.derive(documents: [doc(.gpay, 2026, 9, 2026, 9, id: id)], pinnedMonths: [])
        guard case .present(let ids) = grid.state(month: YearMonth(year: 2026, month: 9), source: .gpay) else {
            return XCTFail("expected present")
        }
        XCTAssertEqual(ids, [id])
    }

    func testPinnedFutureMonthAppearsAwaiting() {
        let grid = CoverageGrid.derive(documents: [doc(.paytm, 2026, 8, 2026, 8)],
                                       pinnedMonths: [YearMonth(year: 2026, month: 10)])
        XCTAssertEqual(grid.months.first, YearMonth(year: 2026, month: 10))
        for source in Source.allCases {
            guard case .awaiting = grid.state(month: YearMonth(year: 2026, month: 10), source: source) else {
                return XCTFail("pinned month should be all-awaiting")
            }
        }
    }

    func testGapMonthsAreFilled() {
        let grid = CoverageGrid.derive(documents: [doc(.gpay, 2026, 5, 2026, 5), doc(.gpay, 2026, 8, 2026, 8)],
                                       pinnedMonths: [])
        XCTAssertEqual(grid.months, [
            YearMonth(year: 2026, month: 8), YearMonth(year: 2026, month: 7),
            YearMonth(year: 2026, month: 6), YearMonth(year: 2026, month: 5),
        ])
        guard case .awaiting = grid.state(month: YearMonth(year: 2026, month: 6), source: .gpay) else {
            return XCTFail("gap month should be awaiting")
        }
    }

    func testEmptyInputsYieldEmptyGrid() {
        let grid = CoverageGrid.derive(documents: [], pinnedMonths: [])
        XCTAssertTrue(grid.months.isEmpty)
    }
}
