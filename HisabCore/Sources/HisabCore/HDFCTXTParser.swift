import Foundation

/// Parser for HDFC's delimited .txt statement export — fixed-width columns whose
/// exact extents come from the dash ruler under the header:
///
///     Date      Narration              Chq./Ref.No.   Value Dt  Withdrawal ... Balance
///     --------  ---------------------  -------------  --------  ---------- ... -------
///     03/03/26  UPI-…                  0000119436…    03/03/26      30.00      35,694.53
///               continuation of narration…
///
/// Table semantics (direction, chain verification, refs) are shared with the PDF
/// parser via HDFCStatementTable, so both renditions produce identical identities.
public struct HDFCTXTParser: StatementParser {
    public let source = Source.hdfc

    public init() {}

    private static func decode(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    public func canParse(data: Data, filename: String) -> Bool {
        guard !data.starts(with: Array("%PDF".utf8)), !data.starts(with: [0x50, 0x4B]),
              let text = Self.decode(data) else { return false }
        return text.contains("HDFC BANK Ltd.") && text.contains("Statement of accounts")
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let text = Self.decode(data) else { throw ParseError.unrecognizedFormat }
        let lines = text.components(separatedBy: .newlines)

        guard let ruler = lines.first(where: { Self.isRuler($0) }),
              case let columns = Self.dashRanges(in: ruler), columns.count == 7 else {
            throw ParseError.unrecognizedFormat
        }

        func cell(_ line: [Character], _ index: Int) -> String {
            let range = columns[index]
            guard line.count > range.lowerBound else { return "" }
            // A column may bleed a couple of characters past its ruler on the right.
            let upper = min(line.count, index + 1 < columns.count
                            ? columns[index + 1].lowerBound - 1 : line.count)
            return String(line[range.lowerBound..<max(range.lowerBound, upper)])
                .trimmingCharacters(in: .whitespaces)
        }

        var rows: [HDFCRow] = []
        var open: HDFCRow?

        for rawLine in lines {
            if rawLine.contains("STATEMENT SUMMARY") { break }
            if Self.isFence(rawLine) || Self.isRuler(rawLine) {
                if let finished = open { rows.append(finished); open = nil }
                continue
            }
            let chars = Array(rawLine)
            let date = cell(chars, 0)
            if date.wholeMatch(of: #/\d{2}/\d{2}/\d{2}/#) != nil {
                if let finished = open { rows.append(finished) }
                open = HDFCRow(dateText: date,
                               narration: cell(chars, 1),
                               refText: cell(chars, 2).isEmpty ? nil : cell(chars, 2),
                               withdrawalText: cell(chars, 4).isEmpty ? nil : cell(chars, 4),
                               depositText: cell(chars, 5).isEmpty ? nil : cell(chars, 5),
                               balanceText: cell(chars, 6).isEmpty ? nil : cell(chars, 6))
                continue
            }
            // Narration continuation: date and every non-narration cell blank.
            if open != nil, date.isEmpty {
                let continuation = cell(chars, 1)
                if !continuation.isEmpty,
                   cell(chars, 2).isEmpty, cell(chars, 4).isEmpty,
                   cell(chars, 5).isEmpty, cell(chars, 6).isEmpty {
                    open!.narration += " " + continuation
                }
            }
        }
        if let finished = open { rows.append(finished) }

        return try HDFCStatementTable.parse(rows: rows,
                                            openingBalancePaise: Self.openingBalance(in: text),
                                            period: Self.period(in: text))
    }

    static func isRuler(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 20 && trimmed.allSatisfy { $0 == "-" || $0 == " " }
            && trimmed.contains("--")
    }

    static func dashRanges(in ruler: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for (index, char) in ruler.enumerated() {
            if char == "-" {
                if start == nil { start = index }
            } else if let s = start {
                ranges.append(s..<index)
                start = nil
            }
        }
        if let s = start { ranges.append(s..<ruler.count) }
        return ranges
    }

    static func isFence(_ line: String) -> Bool {
        line.contains("HDFC BANK Ltd") || line.contains("Page No .:")
            || line.contains("Statement of accounts") || line.contains("Statement From")
            || line.contains("Chq./Ref.No.") || line.contains("Account Branch")
            || line.contains("Registered Office") || line.contains("GSTIN")
            || line.contains("End Of Statement")
    }

    static func period(in text: String) -> DatePeriod? {
        guard let match = text.firstMatch(of: #/Statement From\s*:\s*(\d{2}/\d{2}/\d{4})\s+To\s*:\s*(\d{2}/\d{2}/\d{4})/#) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        guard let start = formatter.date(from: String(match.1)),
              let end = formatter.date(from: String(match.2)) else { return nil }
        return DatePeriod(start: start, end: end)
    }

    static func openingBalance(in text: String) -> Int64? {
        guard let match = text.firstMatch(of: #/Opening Balance[^\n]*\n\s*([\d,]+\.\d{2})/#) else {
            return nil
        }
        return Money.signedPaise(fromDecimalString: String(match.1))
    }
}
