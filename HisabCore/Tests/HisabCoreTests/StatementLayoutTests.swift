import XCTest
@testable import HisabCore

/// Synthetic pages laid out like the two real statements the layout reader was
/// built against (positions copied from their PDFs; y grows up the page).
final class StatementLayoutTests: XCTestCase {
    private func f(_ text: String, _ minX: Double, _ maxX: Double, _ y: Double) -> TextFragment {
        TextFragment(text: text, minX: minX, maxX: maxX, minY: y, maxY: y + 9)
    }

    /// HDFC: one header line with "Narration" centred over left-aligned text,
    /// narration hanging below its date at the row pitch, later pages without
    /// the header but with the account block repeated.
    private func hdfcRow(_ y: Double, date: String, narration: [String], ref: String,
                         withdrawal: String = "", deposit: String = "", balance: String) -> [TextFragment] {
        var row = [f(date, 33.7, 62.1, y), f(ref, 288.6, 352.6, y), f(date, 362.5, 390.9, y),
                   f(balance, 594.7, 626.7, y)]
        if !withdrawal.isEmpty { row.append(f(withdrawal, 452.2, 470.2, y)) }
        if !deposit.isEmpty { row.append(f(deposit, 517.0, 535.9, y)) }
        for (i, line) in narration.enumerated() {
            row.append(f(line, i == 0 ? 72 : 68, 72 + Double(line.count) * 4.2, y - Double(i) * 17.2))
        }
        return row
    }

    private var hdfcAccountBlock: [TextFragment] {
        [f("Account No : 50100322613293", 340.2, 492.1, 685.5),
         f("From : 01/04/2025", 34.0, 98.0, 618.2), f("To : 31/03/2026", 154.0, 209.6, 618.2),
         f("Statement of account", 340.2, 441.5, 616.9)]
    }

    private var hdfcPages: [[TextFragment]] {
        let header = [f("Date", 39.9, 55.9, 600.1), f("Narration", 144.2, 178.4, 600.1),
                      f("Chq./Ref.No.", 283.5, 328.2, 600.1), f("Value Dt", 361.5, 391.9, 600.1),
                      f("Withdrawal Amt.", 405.3, 465.8, 600.1), f("Deposit Amt.", 491.1, 535.9, 600.1),
                      f("Closing Balance", 564.3, 619.2, 600.1)]
        let footer = [f("HDFC BANK LIMITED", 34.0, 200.0, 40.0), f("Page No .: 1", 540.0, 590.0, 30.0)]
        let page1 = hdfcAccountBlock + header + footer
            + hdfcRow(582.5, date: "01/04/25", narration: ["UPI-SAHUL", "HAMEED-Q249795806@YBL", "UPI-102422789385-UPI"],
                      ref: "0000102422789385", withdrawal: "14.00", balance: "10,041.58")
            + hdfcRow(530.9, date: "02/04/25", narration: ["NEFT CR-IDFB0010201-MR", "VEDANT SAB"],
                      ref: "0000509553372468", deposit: "2,000.00", balance: "12,041.58")
        let page2 = hdfcAccountBlock + footer
            + [f("OO-IDFBN52025", 72, 130, 599.7)]
            + hdfcRow(582.5, date: "03/04/25", narration: ["UPI-SWIGGY"],
                      ref: "0000102448862938", withdrawal: "436.00", balance: "11,605.58")
        return [page1, page2]
    }

    func testHangingNarrationsAndPageSpill() throws {
        let table = try XCTUnwrap(StatementLayout.table(pages: hdfcPages))
        XCTAssertEqual(table.rows, [
            ["Date", "Narration", "Chq./Ref.No.", "Value Dt", "Withdrawal Amt.", "Deposit Amt.", "Closing Balance"],
            ["01/04/25", "UPI-SAHUL HAMEED-Q249795806@YBL UPI-102422789385-UPI", "0000102422789385", "01/04/25",
             "14.00", "", "10,041.58"],
            // The repeated "To : 31/03/2026" sits just above page 2's spill line
            // but is page furniture, not narration.
            ["02/04/25", "NEFT CR-IDFB0010201-MR VEDANT SAB OO-IDFBN52025", "0000509553372468", "02/04/25",
             "", "2,000.00", "12,041.58"],
            ["03/04/25", "UPI-SWIGGY", "0000102448862938", "03/04/25", "436.00", "", "11,605.58"],
        ])
    }

    func testHangingTableClosesTheBalanceChain() throws {
        let table = try XCTUnwrap(StatementLayout.table(pages: hdfcPages))
        let result = try XCTUnwrap(ColumnInference.infer(table: table))
        XCTAssertEqual(result.transactions.map(\.amountPaise), [1400, 2_000_00, 436_00])
        XCTAssertEqual(result.transactions.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual(result.mapping.dateFormat, "dd/MM/yy")
    }

    /// IDFC: stacked two-line header labels, a summary block and an opening
    /// balance line above the table, multi-line narration centred on its date,
    /// and a row whose narration runs onto the next page above that page's
    /// own first (centred) row.
    private var idfcPages: [[TextFragment]] {
        let header = [f("Transaction", 47.0, 91.9, 349.0), f("Date", 60.8, 78.1, 338.1),
                      f("Value Date", 128.1, 168.5, 338.1), f("Particulars", 219.6, 261.0, 338.1),
                      f("Cheque", 304.5, 333.8, 349.0), f("No", 313.8, 324.5, 338.1),
                      f("Debit", 374.9, 394.9, 338.1), f("Credit", 452.2, 475.3, 338.1),
                      f("Balance", 527.2, 557.9, 338.1)]
        func dates(_ text: String, _ y: Double) -> [TextFragment] { [f(text, 35.0, 80.8, y), f(text, 113.9, 159.7, y)] }
        func narration(_ text: String, _ y: Double) -> TextFragment { f(text, 192.7, 192.7 + Double(text.count) * 4.5, y) }
        let page1 = [f("Opening Balance", 66.3, 131.7, 408.3), f("Total Debit", 216.6, 257.4, 408.3),
                     f("Total Credit", 353.1, 396.9, 408.3), f("Closing Balance", 481.9, 544.1, 408.3),
                     f("11,16,221.76", 116.9, 163.0, 392.5), f("5,000.00", 254.3, 301.0, 392.5),
                     f("3,03,594.00", 392.3, 439.0, 392.5), f("14,14,815.76", 530.3, 577.0, 392.5)]
            + header
            + [narration("Opening Balance", 318.4), f("11,16,221.76", 529.7, 576.0, 318.4)]
            + [narration("NEFT/", 301.7), narration("HDFCH0083/", 290.7), narration("INFURNIA", 279.8)]
            + dates("02-Mar-2026", 268.9)
            + [narration("TECH LIMITED/", 268.9), f("3,03,594.00", 455.9, 498.1, 268.9), f("14,19,815.76", 530.3, 577.0, 268.9)]
            + [narration("CONSOLIDATED", 258.0), narration("MUMBAI,400018,", 247.1)]
            + dates("04-Mar-2026", 225.9) + [narration("POS-VISA/", 225.9)]
            + [narration("Mcafee/606205789898", 220.4), f("1,999.00", 388.1, 419.3, 220.4), f("14,17,816.76", 530.3, 577.0, 220.4)]
            + [narration("NACH/NSEMFS", 204.7)]
            + dates("05-Mar-2026", 193.8)
            + [narration("05032026/5950864403", 193.8), f("5,000.00", 388.1, 419.3, 193.8), f("14,12,816.76", 530.3, 577.0, 193.8)]
            + [narration("ACCOUNT ENTRY", 182.9)]
            + [f("REGISTERED OFFICE: IDFC FIRST BANK LIMITED, Chennai-600031", 45.9, 567.9, 34.6)]
        let page2 = header.map { f($0.text, $0.minX, $0.maxX, $0.minY + 239.2) }
            + [narration("SANDOZ HOUSE", 558.5), narration("MUMBAI,MAHARASHTRA,", 547.6)]
            + [narration("UPI/DR/612093821871/", 531.9)]
            + dates("06-Mar-2026", 521.0)
            + [narration("SANGEETH/", 521.0), f("706.00", 394.8, 419.3, 521.0), f("14,12,110.76", 530.9, 577.0, 521.0)]
            + [narration("HDFC/7560912/UPI", 510.0)]
            + [f("REGISTERED OFFICE: IDFC FIRST BANK LIMITED, Chennai-600031", 45.9, 567.9, 34.6)]
        return [page1, page2]
    }

    func testCentredNarrationsStackedHeaderAndOpeningBalance() throws {
        let table = try XCTUnwrap(StatementLayout.table(pages: idfcPages))
        XCTAssertEqual(table.rows, [
            ["Transaction Date", "Value Date", "Particulars", "Cheque No", "Debit", "Credit", "Balance"],
            ["02-Mar-2026", "02-Mar-2026", "NEFT/ HDFCH0083/ INFURNIA TECH LIMITED/ CONSOLIDATED MUMBAI,400018,",
             "", "", "3,03,594.00", "14,19,815.76"],
            ["04-Mar-2026", "04-Mar-2026", "POS-VISA/ Mcafee/606205789898", "", "1,999.00", "", "14,17,816.76"],
            ["05-Mar-2026", "05-Mar-2026", "NACH/NSEMFS 05032026/5950864403 ACCOUNT ENTRY SANDOZ HOUSE MUMBAI,MAHARASHTRA,",
             "", "5,000.00", "", "14,12,816.76"],
            ["06-Mar-2026", "06-Mar-2026", "UPI/DR/612093821871/ SANGEETH/ HDFC/7560912/UPI", "", "706.00", "", "14,12,110.76"],
        ])
        let result = try XCTUnwrap(ColumnInference.infer(table: table))
        XCTAssertEqual(result.transactions.map(\.amountPaise), [3_03_594_00, 1_999_00, 5_000_00, 706_00])
        let day = YearMonth.istCalendar.dateComponents([.year, .month, .day], from: result.transactions[0].date)
        XCTAssertEqual([day.year, day.month, day.day], [2026, 3, 2])
    }

    func testNoHeaderMeansNoTable() {
        let page = [f("01/04/25", 33.7, 62.1, 582.5), f("UPI-SAHUL", 72, 114, 582.5), f("10,041.58", 594.7, 626.7, 582.5)]
        XCTAssertNil(StatementLayout.table(pages: [page]))
    }

    func testDateWithNoAmountIsNotARow() throws {
        var pages = hdfcPages
        // A dated line in the table area with nothing in any amount column.
        pages[0] += [f("15/04/25", 33.7, 62.1, 300.0), f("Generated on", 72, 130, 300.0)]
        let table = try XCTUnwrap(StatementLayout.table(pages: pages))
        XCTAssertFalse(table.rows.contains { $0[0] == "15/04/25" })
    }
}
