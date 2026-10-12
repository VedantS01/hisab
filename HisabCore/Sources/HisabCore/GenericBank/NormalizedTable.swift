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
            // Most statements print one cell per text run, so positions are
            // what make the table; plain lines are the fallback.
            if let table = StatementLayout.table(pages: fragments(in: doc)) { return table }
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

    #if canImport(PDFKit)
    /// Every page's text runs with their bounds, as PDFKit groups them by line.
    static func fragments(in doc: PDFDocument) -> [[TextFragment]] {
        (0..<doc.pageCount).map { index in
            guard let page = doc.page(at: index),
                  let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
            let text = (page.string ?? "") as NSString
            return selection.selectionsByLine().flatMap { split(run: $0, on: page, text: text) }
        }
    }

    /// PDFKit joins neighbouring runs on a line when the gap is narrow, so a
    /// long narration can swallow the amount beside it ("…/06:23:34 5,97,803.00").
    /// A run holding a number or a date is re-measured word by word — selections
    /// of a character range are exact where `characterBounds` is not — and cut
    /// wherever two words sit further apart than half the line height.
    static func split(run: PDFSelection, on page: PDFPage, text: NSString) -> [TextFragment] {
        let b = run.bounds(for: page)
        let whole = TextFragment(text: run.string ?? "", minX: b.minX, maxX: b.maxX, minY: b.minY, maxY: b.maxY)
        guard run.numberOfTextRanges(on: page) == 1 else { return [whole] }
        let range = run.range(at: 0, on: page)
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { return [whole] }
        let words = text.substring(with: range).split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > 1, words.contains(where: {
            Money.signedPaise(fromDecimalString: String($0)) != nil || DateShapes.looksLikeDate(String($0))
        }) else { return [whole] }

        var pieces: [TextFragment] = []
        var offset = range.location
        for word in words {
            let length = (String(word) as NSString).length
            defer { offset += length + 1 }
            guard length > 0, let w = page.selection(for: NSRange(location: offset, length: length)) else { continue }
            let wb = w.bounds(for: page)
            if let last = pieces.last, wb.minX - last.maxX <= b.height / 2 {
                pieces[pieces.count - 1].text += " " + word
                pieces[pieces.count - 1].maxX = max(last.maxX, wb.maxX)
            } else {
                pieces.append(TextFragment(text: String(word), minX: wb.minX, maxX: wb.maxX, minY: b.minY, maxY: b.maxY))
            }
        }
        return pieces.isEmpty ? [whole] : pieces
    }
    #endif

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
