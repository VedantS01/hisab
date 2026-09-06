import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Text-layer parser for Paytm "UPI Statement" PDFs. Block shape:
///
///     02 Sep                      (no year — inferred from the header period)
///     7:33 PM
///     Paid to FirstClub           (may wrap; "Received from …" for credits)
///     UPI ID: …                    (optional)
///     UPI Ref No: 624536311139
///     Note: …  /  Tag: + "# …"     (optional)
///     HDFC Bank -                  (account column, wraps)
///     93
///     - Rs.453                     ("+ Rs.600" for credits)
///
/// PDFKit's reading order interleaves amounts inline on some pages and emits them
/// all after the blocks on others, so each page pairs its k-th block with its k-th
/// signed amount. Signed amounts before a page's first block (the page-1 summary)
/// are ignored. A page header can arrive glued to the first date
/// ("…Your Account 24 Aug").
public enum PaytmPDFText {
    private static var dateRegex: Regex<Substring> { /^\d{2} [A-Z][a-z]{2}$/ }
    private static var timeRegex: Regex<(Substring, Substring)> { /^\d{1,2}:\d{2}[\u{202F} ]?(AM|PM)$/ }
    private static var amountRegex: Regex<(Substring, Substring, Substring)> { /^([+-]) ?Rs\.([\d,]+(?:\.\d{1,2})?)$/ }

    public static func parse(pages: [String]) throws -> ParsedDocument {
        let allLines = pages.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let period = PaytmXLSXParser.period(in: allLines) else {
            throw ParseError.unrecognizedFormat
        }

        var blocks: [[String]] = []
        var amounts: [Int64] = []  // signed paise, in stream order

        for page in pages {
            var pageBlocks: [[String]] = []
            var pageAmounts: [Int64] = []
            var current: [String]?

            for rawLine in page.components(separatedBy: .newlines) {
                var line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }

                // Header glued to the first date of the page.
                if let range = line.range(of: "Your Account ") {
                    let suffix = String(line[range.upperBound...])
                    if suffix.wholeMatch(of: dateRegex) != nil { line = suffix }
                }

                if let match = line.wholeMatch(of: amountRegex) {
                    if current != nil || !pageBlocks.isEmpty {  // ignore pre-table summary amounts
                        let magnitude = Money.signedPaise(fromDecimalString: String(match.2)) ?? 0
                        pageAmounts.append(match.1 == "-" ? -magnitude : magnitude)
                    }
                    continue
                }
                if line.wholeMatch(of: dateRegex) != nil {
                    if let block = current { pageBlocks.append(block) }
                    current = [line]
                    continue
                }
                current?.append(line)
            }
            if let block = current { pageBlocks.append(block) }
            guard pageBlocks.count == pageAmounts.count else {
                throw ParseError.malformedRow(0, "page has \(pageBlocks.count) blocks but \(pageAmounts.count) amounts")
            }
            blocks += pageBlocks
            amounts += pageAmounts
        }
        guard !blocks.isEmpty else { throw ParseError.empty }

        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd MMM yyyy h:mm a"

        let startYear = YearMonth(date: period.start).year
        let endYear = YearMonth(date: period.end).year
        var previousDate: Date?
        var transactions: [ParsedTransaction] = []

        for (block, signedPaise) in zip(blocks, amounts) {
            guard block.count >= 3, block[1].wholeMatch(of: timeRegex) != nil else {
                throw ParseError.malformedRow(0, block.joined(separator: " | "))
            }
            let time = block[1].replacingOccurrences(of: "\u{202F}", with: " ")

            // Year inference: the candidate that falls inside the statement period wins;
            // ties (period spanning the same month twice) resolve via the statement's
            // newest-first ordering.
            var date: Date?
            for year in Set([endYear, startYear]).sorted(by: >) {
                guard let candidate = formatter.date(from: "\(block[0]) \(year) \(time)"),
                      candidate >= period.start, candidate <= period.end else { continue }
                if let chosen = date {
                    if let previous = previousDate, candidate <= previous, chosen > previous {
                        date = candidate
                    }
                } else {
                    date = candidate
                }
            }
            guard let date else {
                throw ParseError.malformedRow(0, block[0])
            }
            previousDate = date

            let fieldPrefixes = ["UPI ID:", "UPI Ref No:", "Note:", "Tag:", "#"]
            var detailLines: [String] = []
            for line in block.dropFirst(2) {
                if fieldPrefixes.contains(where: { line.hasPrefix($0) }) { break }
                detailLines.append(line)
            }
            guard let detail = detailLines.first else {
                throw ParseError.malformedRow(0, block.joined(separator: " | "))
            }
            var counterparty = detailLines.joined(separator: " ")
            for prefix in ["Paid to ", "Received from ", "Money sent to "] where detail.hasPrefix(prefix) {
                counterparty = String(counterparty.dropFirst(prefix.count))
                break
            }
            let reference = block.first { $0.hasPrefix("UPI Ref No:") }
                .map { $0.dropFirst("UPI Ref No:".count).trimmingCharacters(in: .whitespaces) }

            transactions.append(ParsedTransaction(
                date: date,
                amountPaise: abs(signedPaise),
                direction: signedPaise < 0 ? .debit : .credit,
                counterparty: counterparty,
                reference: reference,
                narration: block.dropFirst(2).joined(separator: " / ")))
        }

        return ParsedDocument(source: .paytm, declaredPeriod: period, transactions: transactions)
    }
}

#if canImport(PDFKit)
public struct PaytmPDFParser: StatementParser {
    public let source = Source.paytm

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: Array("%PDF".utf8)) else { return false }
        guard let doc = PDFDocument(data: data) else { return false }
        if doc.isLocked {
            return filename.lowercased().contains("paytm")
        }
        return doc.page(at: 0)?.string?.contains("Paytm Statement for") ?? false
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let doc = PDFDocument(data: data) else { throw ParseError.unrecognizedFormat }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw ParseError.passwordRequired
            }
        }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        return try PaytmPDFText.parse(pages: pages)
    }
}
#endif
