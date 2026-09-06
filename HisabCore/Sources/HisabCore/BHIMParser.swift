import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Parser for BHIM "Transaction History" PDF exports. One line per transaction:
///
///     06/09/2026 11:51:59 HDFC BANK LTD XXXX3293 sender@upi(NAME) receiver@upi(NAME)
///         115159963311 PAY 219.00 DR SUCCESS
///
/// Only SUCCESS rows are recorded — failed/pending UPI attempts move no money.
/// The counterparty is the *other* party's bracketed name (receiver for debits,
/// sender for credits); BHIM masks names, so they are kept verbatim.
public enum BHIMStatementText {
    private static var rowRegex: Regex<(Substring, Substring, Substring, Substring, Substring, Substring, Substring, Substring, Substring)> {
        #/^(\d{2}/\d{2}/\d{4}) (\d{2}:\d{2}:\d{2}) (.+?) (\S+) (PAY|COLLECT) ([\d,]+\.\d{1,2}) (DR|CR) ([A-Z]+)$/#
    }
    private static var periodRegex: Regex<(Substring, Substring, Substring)> {
        #/Transaction History from (\d{2}/\d{2}/\d{4}) to (\d{2}/\d{2}/\d{4})/#
    }
    private static var partyRegex: Regex<(Substring, Substring, Substring)> {
        /(\S+)\(([^)]*)\)/
    }

    public static func parse(text: String) throws -> ParsedDocument {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = YearMonth.istCalendar
        dateFormatter.timeZone = YearMonth.istCalendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"

        var declaredPeriod: DatePeriod?
        if let match = text.firstMatch(of: periodRegex),
           let start = dateFormatter.date(from: "\(match.1) 00:00:00"),
           let end = dateFormatter.date(from: "\(match.2) 23:59:59") {
            declaredPeriod = DatePeriod(start: start, end: end)
        }

        var transactions: [ParsedTransaction] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.wholeMatch(of: rowRegex) else { continue }
            guard match.8 == "SUCCESS" else { continue }
            guard let date = dateFormatter.date(from: "\(match.1) \(match.2)"),
                  let signed = Money.signedPaise(fromDecimalString: String(match.6)) else {
                throw ParseError.malformedRow(0, trimmed)
            }
            let direction: Direction = match.7 == "DR" ? .debit : .credit

            // Middle section: bank name, masked account, then sender(name) receiver(name).
            let parties = String(match.3).matches(of: partyRegex)
            var counterparty = ""
            if parties.count >= 2 {
                let party = direction == .debit ? parties[1] : parties[0]
                counterparty = String(party.2).trimmingCharacters(in: .whitespaces)
                if counterparty.isEmpty { counterparty = String(party.1) }
            } else {
                counterparty = String(match.3.suffix(40))
            }

            transactions.append(ParsedTransaction(
                date: date, amountPaise: abs(signed), direction: direction,
                counterparty: counterparty,
                reference: String(match.4),
                narration: "\(match.3) / \(match.5) / \(match.8)"))
        }
        guard !transactions.isEmpty else { throw ParseError.empty }
        return ParsedDocument(source: .bhim, declaredPeriod: declaredPeriod, transactions: transactions)
    }
}

#if canImport(PDFKit)
public struct BHIMPDFParser: StatementParser {
    public let source = Source.bhim

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: Array("%PDF".utf8)) else { return false }
        guard let doc = PDFDocument(data: data) else { return false }
        if doc.isLocked {
            let name = filename.lowercased()
            return name.contains("bhim") || name.contains("transaction_statement")
        }
        guard let text = doc.page(at: 0)?.string else { return false }
        return text.contains("Transaction History") && text.contains("Pay/Collect")
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let doc = PDFDocument(data: data) else { throw ParseError.unrecognizedFormat }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw ParseError.passwordRequired
            }
        }
        let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        return try BHIMStatementText.parse(text: text)
    }
}
#endif
