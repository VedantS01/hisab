import Foundation

/// Conservative column inference: enumerates candidate mappings for an unknown
/// bank table and accepts a result only when exactly one distinct interpretation
/// closes the balance chain. Zero candidates or conflicting winners mean nil —
/// the engine never guesses.
public enum ColumnInference {
    public struct Result: Sendable {
        public let mapping: ColumnMapping
        public let transactions: [ParsedTransaction]
    }

    static let candidateDateFormats = ["dd/MM/yyyy", "dd/MM/yy", "dd-MM-yyyy",
                                       "dd MMM yyyy", "dd-MMM-yyyy", "dd-MMM-yy",
                                       "yyyy-MM-dd"]

    public static func infer(table: NormalizedTable) -> Result? {
        let headerIndex = detectHeader(rows: table.rows)
        let start = headerIndex.map { $0 + 1 } ?? 0
        var body: [[String]] = []
        for row in table.rows.dropFirst(start) {
            let nonEmpty = row.filter { !$0.isEmpty }.count
            if nonEmpty >= 3 { body.append(row) }
        }
        guard body.count >= 2 else { return nil }

        let width = body.map(\.count).max() ?? 0
        guard width >= 3 else { return nil }

        func cells(_ column: Int) -> [String] {
            body.map { column < $0.count ? $0[column] : "" }
        }

        // Classify columns.
        var dateColumns: [(column: Int, format: String)] = []
        var numericFull: [Int] = []      // every row numeric — balance/amount candidates
        var numericSparse: [Int] = []    // numeric or empty, ≥1 non-empty — debit/credit legs
        var drcrColumns: [Int] = []
        var textColumns: [(column: Int, averageLength: Int)] = []

        for column in 0..<width {
            let values = cells(column)
            if let format = dateFormat(parsingAll: values) {
                dateColumns.append((column, format))
                continue
            }
            let nonEmpty = values.filter { !$0.isEmpty }
            let numericCount = nonEmpty.filter { Money.signedPaise(fromDecimalString: $0) != nil }.count
            if !nonEmpty.isEmpty && numericCount == nonEmpty.count {
                if nonEmpty.count == values.count { numericFull.append(column) }
                numericSparse.append(column)
                continue
            }
            let drcrCount = nonEmpty.filter { ["dr", "cr"].contains($0.lowercased()) }.count
            if !nonEmpty.isEmpty && drcrCount == nonEmpty.count {
                drcrColumns.append(column)
                continue
            }
            if !nonEmpty.isEmpty {
                let total = nonEmpty.reduce(0) { $0 + $1.count }
                textColumns.append((column, total / nonEmpty.count))
            }
        }

        guard let (dateColumn, format) = dateColumns.first, dateColumns.count == 1 else {
            // Multiple date columns (Value Date + Txn Date) are fine — prefer the
            // leftmost; zero means no bank table.
            if let first = dateColumns.first {
                return inferWithDate(dateColumn: first.column, format: first.format,
                                     numericFull: numericFull, numericSparse: numericSparse,
                                     drcrColumns: drcrColumns, textColumns: textColumns,
                                     body: body)
            }
            return nil
        }
        return inferWithDate(dateColumn: dateColumn, format: format,
                             numericFull: numericFull, numericSparse: numericSparse,
                             drcrColumns: drcrColumns, textColumns: textColumns,
                             body: body)
    }

    private static func inferWithDate(dateColumn: Int, format: String,
                                      numericFull: [Int], numericSparse: [Int],
                                      drcrColumns: [Int],
                                      textColumns: [(column: Int, averageLength: Int)],
                                      body: [[String]]) -> Result? {
        // Narration: the longest-averaging text column.
        let narration = textColumns.max(by: { $0.averageLength < $1.averageLength })?.column
        guard let narrationColumn = narration else { return nil }
        // Reference: any other text column (short alphanumeric labels).
        let referenceColumn = textColumns
            .filter { $0.column != narrationColumn }
            .min(by: { $0.averageLength < $1.averageLength })?.column

        var mappings: [ColumnMapping] = []
        for balance in numericFull {
            let others = numericSparse.filter { $0 != balance }
            // (a) separate debit/credit legs
            for debit in others {
                for credit in others where credit != debit {
                    mappings.append(ColumnMapping(date: dateColumn, narration: narrationColumn,
                                                  reference: referenceColumn,
                                                  debit: debit, credit: credit,
                                                  balance: balance, dateFormat: format))
                }
            }
            // (b) single signed amount / (c) amount + DR/CR
            for amount in others where numericFull.contains(amount) {
                mappings.append(ColumnMapping(date: dateColumn, narration: narrationColumn,
                                              reference: referenceColumn,
                                              amount: amount,
                                              balance: balance, dateFormat: format))
                for drcr in drcrColumns {
                    mappings.append(ColumnMapping(date: dateColumn, narration: narrationColumn,
                                                  reference: referenceColumn,
                                                  amount: amount, drcr: drcr,
                                                  balance: balance, dateFormat: format))
                }
            }
        }

        var winners: [(ColumnMapping, [ParsedTransaction])] = []
        for mapping in mappings {
            if case .validated(let txns) = ChainInterpreter.interpret(rows: body, mapping: mapping) {
                winners.append((mapping, txns))
            }
        }
        guard let first = winners.first else { return nil }
        for (_, txns) in winners.dropFirst() where txns != first.1 {
            return nil  // two different valid readings — refuse to choose
        }
        return Result(mapping: first.0, transactions: first.1)
    }

    /// The first row that names columns rather than containing data: ≥2 cells
    /// matching header vocabulary and no date-parseable cell.
    static func detectHeader(rows: [[String]]) -> Int? {
        let keywords = try! NSRegularExpression(
            pattern: "date|narration|particular|description|remarks|debit|credit|withdraw|deposit|amount|balance|ref|cheque",
            options: [.caseInsensitive])
        for (index, row) in rows.enumerated() {
            var keywordHits = 0
            var hasDate = false
            for cell in row where !cell.isEmpty {
                let range = NSRange(cell.startIndex..., in: cell)
                if keywords.firstMatch(in: cell, range: range) != nil { keywordHits += 1 }
                if dateFormat(parsingAll: [cell]) != nil { hasDate = true }
            }
            if keywordHits >= 2 && !hasDate { return index }
        }
        return nil
    }

    /// First candidate format under which every non-empty value parses (and at
    /// least one value is non-empty). Nil when the column isn't dates.
    private static func dateFormat(parsingAll values: [String]) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let nonEmpty = values.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }
        for candidate in candidateDateFormats {
            formatter.dateFormat = candidate
            var allParse = true
            for value in nonEmpty where formatter.date(from: value) == nil {
                allParse = false
                break
            }
            if allParse { return candidate }
        }
        return nil
    }
}
