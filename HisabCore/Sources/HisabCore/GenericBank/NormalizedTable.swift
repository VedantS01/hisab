import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// The container-neutral table every generic-bank component consumes: trimmed
/// cell text, ragged rows allowed. Adapters reuse the existing container
/// readers (MinimalZip/XLSX, MinimalXLS, PDFKit) rather than re-parsing.
public struct NormalizedTable: Sendable, Equatable {
    public var rows: [[String]]
    public var container: String  // "csv" | "txt" | "xlsx" | "xls" | "pdf"

    public init(rows: [[String]], container: String) {
        self.rows = rows
        self.container = container
    }

    public static func from(data: Data, filename: String, password: String?) -> NormalizedTable? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "csv":
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let rows = text.split(whereSeparator: \.isNewline).map(splitCSVLine)
            return rows.isEmpty ? nil : NormalizedTable(rows: rows, container: "csv")
        case "txt":
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let rows = text.split(whereSeparator: \.isNewline).map(splitOnSpaceRuns)
            return rows.isEmpty ? nil : NormalizedTable(rows: rows, container: "txt")
        case "xlsx":
            guard let workbook = try? XLSXReader.read(data: data),
                  let sheet = workbook.sheets.values.max(by: { $0.count < $1.count }),
                  !sheet.isEmpty else { return nil }
            return NormalizedTable(rows: densify(xlsxRows: sheet), container: "xlsx")
        case "xls":
            guard let grid = try? MinimalXLS.cells(in: data), !grid.isEmpty else { return nil }
            return NormalizedTable(rows: densify(xlsGrid: grid), container: "xls")
        case "pdf":
            #if canImport(PDFKit)
            guard let doc = PDFDocument(data: data) else { return nil }
            if doc.isLocked {
                guard let password, doc.unlock(withPassword: password) else { return nil }
            }
            var rows: [[String]] = []
            for pageIndex in 0..<doc.pageCount {
                guard let text = doc.page(at: pageIndex)?.string else { continue }
                for line in text.split(whereSeparator: \.isNewline) {
                    let cells = splitOnSpaceRuns(line)
                    if !cells.isEmpty { rows.append(cells) }
                }
            }
            return rows.isEmpty ? nil : NormalizedTable(rows: rows, container: "pdf")
            #else
            return nil
            #endif
        default:
            return nil
        }
    }

    static func splitCSVLine(_ line: Substring) -> [String] {
        var cells: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            switch (ch, inQuotes) {
            case ("\"", _): inQuotes.toggle()
            case (",", false): cells.append(current); current = ""
            default: current.append(ch)
            }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func splitOnSpaceRuns(_ line: Substring) -> [String] {
        line.replacingOccurrences(of: "\t", with: "  ")
            .components(separatedBy: "  ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// XLSX rows arrive as [columnLetter: text]; lay them out densely, A=0.
    private static func densify(xlsxRows: [[String: String]]) -> [[String]] {
        func index(of letters: String) -> Int {
            letters.uppercased().unicodeScalars.reduce(0) { acc, scalar in
                acc * 26 + Int(scalar.value) - 64
            } - 1
        }
        let width = xlsxRows.flatMap { $0.keys.map { index(of: $0) + 1 } }.max() ?? 0
        return xlsxRows.map { row in
            var cells = [String](repeating: "", count: width)
            for (letters, value) in row {
                let i = index(of: letters)
                if i >= 0 && i < width { cells[i] = value.trimmingCharacters(in: .whitespaces) }
            }
            return cells
        }
    }

    /// XLS cells arrive as [rowIndex: [colIndex: text]].
    private static func densify(xlsGrid: [Int: [Int: String]]) -> [[String]] {
        let width = xlsGrid.values.flatMap { $0.keys.map { $0 + 1 } }.max() ?? 0
        return xlsGrid.keys.sorted().map { rowIndex in
            var cells = [String](repeating: "", count: width)
            for (col, value) in xlsGrid[rowIndex] ?? [:] {
                if col >= 0 && col < width { cells[col] = value.trimmingCharacters(in: .whitespaces) }
            }
            return cells
        }
    }
}
