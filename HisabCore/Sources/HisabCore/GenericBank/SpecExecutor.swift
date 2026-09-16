import Foundation

/// Applies a FormatSpec to a NormalizedTable. Returns nil when the spec does
/// not match (no header row), a ChainOutcome otherwise — and `.validated` only
/// when the whole statement closes to the paisa.
public enum SpecExecutor {
    public static func execute(table: NormalizedTable, spec: FormatSpec) -> ChainOutcome? {
        let required = requiredRoles(for: spec.signConvention)
        guard let (headerIndex, columns) = findHeader(table: table, spec: spec,
                                                      required: required) else { return nil }

        var furniture: [NSRegularExpression] = []
        for pattern in spec.furniturePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { return nil }
            furniture.append(regex)
        }

        var body: [[String]] = []
        for row in table.rows.dropFirst(headerIndex + 1) {
            if row.allSatisfy(\.isEmpty) { continue }
            let joined = row.joined(separator: "|")
            if furniture.contains(where: { matches($0, joined) }) { continue }
            body.append(row)
        }
        guard !body.isEmpty else { return .broken(rowIndex: 0, detail: "no body rows") }

        guard let dateFormat = pickDateFormat(spec.dateFormats, body: body,
                                              dateColumn: columns["date"]!) else {
            return .broken(rowIndex: 0, detail: "no declared date format parses the body")
        }

        let mapping = ColumnMapping(date: columns["date"]!,
                                    narration: columns["narration"]!,
                                    reference: columns["reference"],
                                    debit: columns["debit"],
                                    credit: columns["credit"],
                                    amount: columns["amount"],
                                    drcr: columns["drcr"],
                                    balance: columns["balance"]!,
                                    amountIsUnsigned: spec.signConvention == "unsignedChain",
                                    dateFormat: dateFormat,
                                    referencePatterns: spec.referencePatterns ?? [])
        return ChainInterpreter.interpret(rows: body, mapping: mapping)
    }

    static func requiredRoles(for signConvention: String) -> [String] {
        switch signConvention {
        case "debitCredit": return ["date", "narration", "balance", "debit", "credit"]
        case "amountDRCR": return ["date", "narration", "balance", "amount", "drcr"]
        default: return ["date", "narration", "balance", "amount"]
        }
    }

    /// First row where every required role's regex matches a distinct cell.
    private static func findHeader(table: NormalizedTable, spec: FormatSpec,
                                   required: [String]) -> (Int, [String: Int])? {
        var regexes: [String: NSRegularExpression] = [:]
        for (role, pattern) in spec.headerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern,
                                                       options: [.caseInsensitive]) else { return nil }
            regexes[role] = regex
        }
        for role in required where regexes[role] == nil { return nil }

        for (rowIndex, row) in table.rows.enumerated() {
            var columns: [String: Int] = [:]
            var used = Set<Int>()
            var allFound = true
            // Required roles claim cells first, then optional ones.
            let orderedRoles = required + regexes.keys.filter { !required.contains($0) }.sorted()
            for role in orderedRoles {
                guard let regex = regexes[role] else { continue }
                var found: Int?
                for (cellIndex, cell) in row.enumerated()
                where !used.contains(cellIndex) && matches(regex, cell) {
                    found = cellIndex
                    break
                }
                if let found {
                    columns[role] = found
                    used.insert(found)
                } else if required.contains(role) {
                    allFound = false
                    break
                }
            }
            if allFound { return (rowIndex, columns) }
        }
        return nil
    }

    private static func pickDateFormat(_ candidates: [String], body: [[String]],
                                       dateColumn: Int) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for candidate in candidates {
            formatter.dateFormat = candidate
            var allParse = true
            for row in body {
                let text = dateColumn < row.count ? row[dateColumn] : ""
                if formatter.date(from: text) == nil { allParse = false; break }
            }
            if allParse { return candidate }
        }
        return nil
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
