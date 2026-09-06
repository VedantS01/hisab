import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Text-layer parser for Google Pay "Transaction statement" PDFs, operating on the
/// line stream PDFKit extracts. Block shape (observed on real statements):
///
///     03 Mar, 2026
///     01:09 PM
///     Paid to MERCHANT NAME            (or "Received from …"; may wrap lines)
///     UPI Transaction ID: 119436467750
///     Paid by HDFC Bank 3293           (credits: "Paid to <own bank>")
///     ₹1,122                            (Indian grouping, optional decimals)
///
/// Known statement quirk: GPay can list one UPI transaction twice under different
/// counterparty names (observed with promo credits). Same reference = same money
/// movement, so downstream content-hash dedup correctly collapses such pairs.
public enum GPayStatementText {
    private static var dateRegex: Regex<Substring> { /^\d{2} [A-Z][a-z]{2}, \d{4}$/ }
    private static var timeRegex: Regex<(Substring, Substring)> { /^\d{2}:\d{2}[\u{202F} ]?(AM|PM)$/ }
    private static var pageRegex: Regex<Substring> { /^Page \d+ of \d+$/ }
    private static var periodRegex: Regex<(Substring, Substring, Substring)> { /^(\d{2} [A-Za-z]+ \d{4}) - (\d{2} [A-Za-z]+ \d{4})$/ }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = YearMonth.istCalendar
        f.timeZone = YearMonth.istCalendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    public static func parse(_ text: String) throws -> ParsedDocument {
        let dayFormatter = formatter("dd MMM, yyyy hh:mm a")
        let periodFormatter = formatter("dd MMMM yyyy")

        var declaredPeriod: DatePeriod?
        var transactions: [ParsedTransaction] = []

        // Block-in-progress state
        var blockDate: Date?
        var pendingDateLine: String?
        var counterpartyLines: [String] = []
        var reference: String?
        var bankLine: String?
        var awaitingPeriod = false

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        func resetBlock() {
            blockDate = nil
            pendingDateLine = nil
            counterpartyLines = []
            reference = nil
            bankLine = nil
        }

        for (index, line) in lines.enumerated() {
            let lineNo = index + 1

            if awaitingPeriod {
                awaitingPeriod = false
                if let match = line.wholeMatch(of: periodRegex),
                   let start = periodFormatter.date(from: String(match.1)),
                   let end = periodFormatter.date(from: String(match.2)) {
                    declaredPeriod = DatePeriod(start: start, end: end)
                    continue
                }
            }
            if line == "Transaction statement period" {
                awaitingPeriod = true
                continue
            }

            // Page furniture, headers, footers — never part of a block's interior
            // except that a block can span a page break, so these are skipped even mid-block.
            if line == "Transaction statement"
                || line == "Date & time Transaction details Amount"
                || line.hasPrefix("Note:")
                || line.hasPrefix("received. Any payments")
                || line.wholeMatch(of: pageRegex) != nil {
                continue
            }

            if line.wholeMatch(of: dateRegex) != nil {
                guard blockDate == nil, pendingDateLine == nil else {
                    throw ParseError.malformedRow(lineNo, line)
                }
                pendingDateLine = line
                continue
            }

            if let dateLine = pendingDateLine {
                guard line.wholeMatch(of: timeRegex) != nil,
                      let date = dayFormatter.date(from: "\(dateLine) \(line.replacingOccurrences(of: "\u{202F}", with: " "))") else {
                    throw ParseError.malformedRow(lineNo, line)
                }
                blockDate = date
                pendingDateLine = nil
                continue
            }

            guard blockDate != nil else { continue }  // outside any block (e.g. summary ₹ lines)

            if line.hasPrefix("UPI Transaction ID:") {
                reference = line.dropFirst("UPI Transaction ID:".count)
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("₹") {
                guard let date = blockDate,
                      let first = counterpartyLines.first,
                      let amount = paise(fromRupeeString: line) else {
                    throw ParseError.malformedRow(lineNo, line)
                }
                let direction: Direction
                var name: String
                if first.hasPrefix("Paid to ") {
                    direction = .debit
                    name = String(first.dropFirst("Paid to ".count))
                } else if first.hasPrefix("Received from ") {
                    direction = .credit
                    name = String(first.dropFirst("Received from ".count))
                } else {
                    throw ParseError.malformedRow(lineNo, first)
                }
                if counterpartyLines.count > 1 {
                    name += " " + counterpartyLines.dropFirst().joined(separator: " ")
                }
                var narrationParts = counterpartyLines
                if let reference { narrationParts.append("UPI Transaction ID: \(reference)") }
                if let bankLine { narrationParts.append(bankLine) }
                transactions.append(ParsedTransaction(
                    date: date, amountPaise: amount, direction: direction,
                    counterparty: name, reference: reference,
                    narration: narrationParts.joined(separator: " / ")))
                resetBlock()
                continue
            }

            if reference != nil {
                // After the reference, the bank line ("Paid by …" / "Paid to …").
                bankLine = line
            } else {
                counterpartyLines.append(line)
            }
        }

        if blockDate != nil || pendingDateLine != nil {
            throw ParseError.malformedRow(lines.count, lines.last ?? "")
        }
        guard !transactions.isEmpty else { throw ParseError.empty }
        return ParsedDocument(source: .gpay, declaredPeriod: declaredPeriod, transactions: transactions)
    }

    /// "₹3,47,622.60" -> 34762260 paise. Nil for anything that isn't a rupee amount.
    public static func paise(fromRupeeString raw: String) -> Int64? {
        guard raw.hasPrefix("₹") else { return nil }
        let cleaned = raw.dropFirst().replacingOccurrences(of: ",", with: "")
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let rupees = Int64(parts[0]), rupees >= 0 else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            let digits = parts[1]
            guard (1...2).contains(digits.count), let value = Int64(digits) else { return nil }
            fraction = digits.count == 1 ? value * 10 : value
        }
        return rupees * 100 + fraction
    }
}

#if canImport(PDFKit)
/// PDFKit wrapper: extracts page text and delegates to GPayStatementText.
public struct GPayPDFParser: StatementParser {
    public let source = Source.gpay

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: Array("%PDF".utf8)) else { return false }
        guard let doc = PDFDocument(data: data) else { return false }
        if doc.isLocked {
            return filename.lowercased().contains("gpay")
        }
        return doc.page(at: 0)?.string?.contains("Transaction statement period") ?? false
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let doc = PDFDocument(data: data) else { throw ParseError.unrecognizedFormat }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw ParseError.passwordRequired
            }
        }
        let text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")
        return try GPayStatementText.parse(text)
    }
}
#endif
