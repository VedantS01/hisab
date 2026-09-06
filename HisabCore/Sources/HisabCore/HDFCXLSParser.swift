import Foundation

/// Parser for HDFC's legacy .xls statement export (CDF/BIFF8, read by MinimalXLS).
/// The sheet mirrors the .txt layout — one header row, one row per transaction with
/// separate Withdrawal/Deposit number cells — and shares HDFCStatementTable, so
/// identities match the PDF and TXT renditions exactly.
public struct HDFCXLSParser: StatementParser {
    public let source = Source.hdfc

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard let grid = try? MinimalXLS.cells(in: data) else { return false }
        let texts = grid.values.flatMap(\.values)
        return texts.contains("Chq./Ref.No.") && texts.contains { $0.contains("HDFC BANK") }
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        let grid: [Int: [Int: String]]
        do {
            grid = try MinimalXLS.cells(in: data)
        } catch {
            throw ParseError.unrecognizedFormat
        }

        guard let headerRow = grid.first(where: { $0.value.values.contains("Chq./Ref.No.") }) else {
            throw ParseError.unrecognizedFormat
        }
        func column(_ title: String) -> Int? {
            headerRow.value.first { $0.value == title }?.key
        }
        guard let dateCol = column("Date"),
              let narrationCol = column("Narration"),
              let refCol = column("Chq./Ref.No."),
              let withdrawalCol = column("Withdrawal Amt."),
              let depositCol = column("Deposit Amt."),
              let balanceCol = column("Closing Balance") else {
            throw ParseError.unrecognizedFormat
        }

        var rows: [HDFCRow] = []
        for rowIndex in grid.keys.sorted() where rowIndex > headerRow.key {
            guard let row = grid[rowIndex], let date = row[dateCol],
                  date.wholeMatch(of: #/\d{2}/\d{2}/\d{2}/#) != nil else { continue }
            rows.append(HDFCRow(dateText: date,
                                narration: row[narrationCol] ?? "",
                                refText: row[refCol],
                                withdrawalText: row[withdrawalCol],
                                depositText: row[depositCol],
                                balanceText: row[balanceCol]))
        }

        let allText = grid.values.flatMap(\.values).joined(separator: "\n")
        return try HDFCStatementTable.parse(rows: rows,
                                            openingBalancePaise: nil,
                                            period: HDFCTXTParser.period(in: allText))
    }
}
