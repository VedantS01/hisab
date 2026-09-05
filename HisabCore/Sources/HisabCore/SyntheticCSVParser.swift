import Foundation

/// Demo/test statement format. Header line "hisab-demo-csv,v1"; optional
/// "period,yyyy-MM-dd,yyyy-MM-dd" second line; rows:
/// date,amountPaise,debit|credit,counterparty,reference,narration
public struct SyntheticCSVParser: StatementParser {
    public let source = Source.gpay

    public init() {}

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public func canParse(data: Data, filename: String) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.hasPrefix("hisab-demo-csv,v1")
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("hisab-demo-csv,v1") else {
            throw ParseError.unrecognizedFormat
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        lines.removeFirst()  // header

        var declaredPeriod: DatePeriod?
        if let first = lines.first, first.hasPrefix("period,") {
            let parts = first.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let start = Self.dateFormatter.date(from: String(parts[1])),
                  let end = Self.dateFormatter.date(from: String(parts[2])) else {
                throw ParseError.malformedRow(2, first)
            }
            declaredPeriod = DatePeriod(start: start, end: end)
            lines.removeFirst()
        }

        guard !lines.isEmpty else { throw ParseError.empty }

        var transactions: [ParsedTransaction] = []
        for (offset, line) in lines.enumerated() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6,
                  let date = Self.dateFormatter.date(from: fields[0]),
                  let amount = Int64(fields[1]), amount > 0,
                  let direction = Direction(rawValue: fields[2]) else {
                throw ParseError.malformedRow(offset + (declaredPeriod == nil ? 2 : 3), line)
            }
            transactions.append(ParsedTransaction(
                date: date, amountPaise: amount, direction: direction,
                counterparty: fields[3],
                reference: fields[4].isEmpty ? nil : fields[4],
                narration: fields[5]))
        }
        return ParsedDocument(source: source, declaredPeriod: declaredPeriod, transactions: transactions)
    }
}
