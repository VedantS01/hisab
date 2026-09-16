import Foundation

/// A data-free description of a statement layout Hisab could not read, safe to
/// email: header labels verbatim, body cells only as digit/letter masks. By
/// construction no transaction value, date, narration, or amount can appear.
public struct FormatFingerprint: Codable, Equatable, Sendable {
    public var container: String
    public var headerRow: [String]
    public var columnCount: Int
    public var rowCount: Int          // body rows below the header
    public var cellShapes: [String]   // per-column dominant mask: digits→N, letters→A
    public var bankNameGuess: String?

    /// Fixed nominative list scanned in header/furniture text only.
    static let knownBanks: [(pattern: String, name: String)] = [
        ("state bank|sbi", "SBI"), ("icici", "ICICI"), ("axis", "Axis"),
        ("kotak", "Kotak"), ("hdfc", "HDFC"), ("idfc", "IDFC First"),
        ("punjab national|pnb", "PNB"), ("bank of baroda", "Bank of Baroda"),
        ("canara", "Canara"), ("yes bank", "Yes Bank"), ("federal", "Federal"),
        ("indusind", "IndusInd"), ("union bank", "Union Bank"), ("idbi", "IDBI"),
    ]

    public static func make(table: NormalizedTable) -> FormatFingerprint {
        let headerIndex = ColumnInference.detectHeader(rows: table.rows)
        let headerRow = headerIndex.map { table.rows[$0] } ?? []
        let bodyStart = headerIndex.map { $0 + 1 } ?? 0
        let body = Array(table.rows.dropFirst(bodyStart))
        let width = body.map(\.count).max() ?? headerRow.count

        var shapes: [String] = []
        for column in 0..<width {
            var counts: [String: Int] = [:]
            for row in body where column < row.count && !row[column].isEmpty {
                counts[mask(row[column]), default: 0] += 1
            }
            let dominant = counts.max { $0.value < $1.value }?.key ?? ""
            shapes.append(dominant)
        }

        // Bank name: header row + any furniture rows above it. Never body rows.
        let furnitureText = table.rows.prefix(bodyStart).flatMap { $0 }.joined(separator: " ").lowercased()
        var guess: String?
        for (pattern, name) in knownBanks {
            if furnitureText.range(of: pattern, options: .regularExpression) != nil {
                guess = name
                break
            }
        }

        return FormatFingerprint(container: table.container,
                                 headerRow: headerRow,
                                 columnCount: width,
                                 rowCount: body.count,
                                 cellShapes: shapes,
                                 bankNameGuess: guess)
    }

    /// Digits become N, letters become A; punctuation and spaces survive.
    /// "01/04/2026" → "NN/NN/NNNN", "POS X 12" → "AAA A NN".
    static func mask(_ value: String) -> String {
        String(value.map { ch in
            if ch.isNumber { return "N" }
            if ch.isLetter { return "A" }
            return ch
        })
    }

    public func emailBody(appVersion: String) -> String {
        var lines = ["Hisab format request (v\(appVersion))", ""]
        lines.append("Container: \(container)")
        if let bankNameGuess { lines.append("Bank (guessed): \(bankNameGuess)") }
        lines.append("Columns: \(columnCount), body rows: \(rowCount)")
        if !headerRow.isEmpty {
            lines.append("Header: \(headerRow.joined(separator: " | "))")
        } else {
            lines.append("Header: none detected")
        }
        lines.append("Column shapes: \(cellShapes.joined(separator: " | "))")
        lines.append("")
        lines.append("This report contains column labels and value shapes only — no transactions.")
        return lines.joined(separator: "\n")
    }
}
