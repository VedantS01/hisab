import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Text-layer parser for IDFC FIRST Bank "STATEMENT OF ACCOUNT" PDFs.
///
/// A row starts with a "dd-MMM-yyyy dd-MMM-yyyy" transaction/value date pair
/// (possibly with the first particulars fragment on the same line) and ends at a
/// line whose trailing tokens are two amounts: the transaction amount and the
/// running balance. The text layer merges the Debit and Credit columns, so
/// direction is recovered from the running balance chain — which also makes every
/// row self-validating (a chain break throws instead of guessing).
public enum IDFCStatementText {
    private static var rowStartRegex: Regex<(Substring, Substring, Substring)> {
        /^(\d{2}-[A-Za-z]{3}-\d{4}) \d{2}-[A-Za-z]{3}-\d{4}(.*)$/
    }
    private static var terminatorRegex: Regex<(Substring, Substring, Substring, Substring)> {
        /^(.*?)\s*([\d,]+\.\d{2}) ([\d,]+\.\d{2})$/
    }
    private static var periodRegex: Regex<(Substring, Substring, Substring)> {
        /^STATEMENT PERIOD : (\d{4}-\d{2}-\d{2}) TO (\d{4}-\d{2}-\d{2})$/
    }
    private static var openingRegex: Regex<(Substring, Substring)> {
        /^Opening Balance ([\d,]+\.\d{2})$/
    }
    private static var fourAmountsRegex: Regex<Substring> {
        /^[\d,]+\.\d{2} [\d,]+\.\d{2} [\d,]+\.\d{2} [\d,]+\.\d{2}$/
    }

    /// Page furniture that can interrupt even an open row at a page break.
    private static func isFurniture(_ line: String) -> Bool {
        line == "STATEMENT OF ACCOUNT"
            || line.hasPrefix("CUSTOMER ID :") || line.hasPrefix("ACCOUNT NO :")
            || line.hasPrefix("STATEMENT PERIOD :")
            || line == "Opening Balance Total Debit Total Credit Closing Balance"
            || line == "Transaction"
            || line == "Date Value Date Particulars Cheque"
            || line == "No Debit Credit Balance"
            || line.hasPrefix("REGISTERED OFFICE:")
            || line.wholeMatch(of: /^Page \d+ of \d+$/) != nil
            || line.wholeMatch(of: fourAmountsRegex) != nil
    }

    public static func parse(pages: [String]) throws -> ParsedDocument {
        let lines = pages.flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let isoFormatter = DateFormatter()
        isoFormatter.calendar = YearMonth.istCalendar
        isoFormatter.timeZone = YearMonth.istCalendar.timeZone
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let rowFormatter = DateFormatter()
        rowFormatter.calendar = YearMonth.istCalendar
        rowFormatter.timeZone = YearMonth.istCalendar.timeZone
        rowFormatter.locale = Locale(identifier: "en_US_POSIX")
        rowFormatter.dateFormat = "dd-MMM-yyyy"

        var declaredPeriod: DatePeriod?
        var previousBalance: Int64?
        var currentDate: Date?
        var particulars = ""
        var transactions: [ParsedTransaction] = []

        func append(_ fragment: String) {
            let piece = fragment.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { return }
            if particulars.isEmpty || particulars.hasSuffix("/") {
                particulars += piece
            } else {
                particulars += " " + piece
            }
        }

        func closeRow(amountText: String, balanceText: String, line: String) throws {
            guard let date = currentDate,
                  let amount = Money.signedPaise(fromDecimalString: amountText),
                  let balance = Money.signedPaise(fromDecimalString: balanceText),
                  let previous = previousBalance else {
                throw ParseError.malformedRow(0, line)
            }
            let direction: Direction
            if previous - amount == balance {
                direction = .debit
            } else if previous + amount == balance {
                direction = .credit
            } else {
                throw ParseError.malformedRow(0, "balance chain break at: \(line)")
            }
            let (counterparty, reference) = Self.extract(from: particulars)
            transactions.append(ParsedTransaction(
                date: date, amountPaise: amount, direction: direction,
                counterparty: counterparty,
                reference: reference ?? Self.syntheticReference(balancePaise: balance, date: date,
                                                                amountPaise: amount),
                narration: particulars))
            previousBalance = balance
            currentDate = nil
            particulars = ""
        }

        for line in lines {
            if declaredPeriod == nil, let match = line.wholeMatch(of: periodRegex),
               let start = isoFormatter.date(from: String(match.1)),
               let end = isoFormatter.date(from: String(match.2)) {
                declaredPeriod = DatePeriod(start: start, end: end)
                continue
            }
            if isFurniture(line) { continue }
            if previousBalance == nil, let match = line.wholeMatch(of: openingRegex) {
                previousBalance = Money.signedPaise(fromDecimalString: String(match.1))
                continue
            }

            if let match = line.wholeMatch(of: rowStartRegex) {
                guard currentDate == nil else {
                    throw ParseError.malformedRow(0, "row started before previous closed: \(line)")
                }
                guard let date = rowFormatter.date(from: String(match.1)) else {
                    throw ParseError.malformedRow(0, line)
                }
                currentDate = date
                particulars = ""
                let rest = String(match.2)
                // The first fragment can itself end in "amount balance" (single-line row).
                if let terminator = rest.trimmingCharacters(in: .whitespaces)
                    .wholeMatch(of: terminatorRegex) {
                    append(String(terminator.1))
                    try closeRow(amountText: String(terminator.2),
                                 balanceText: String(terminator.3), line: line)
                } else {
                    append(rest)
                }
                continue
            }

            guard currentDate != nil else { continue }  // outside any row

            if let match = line.wholeMatch(of: terminatorRegex) {
                append(String(match.1))
                try closeRow(amountText: String(match.2), balanceText: String(match.3), line: line)
            } else {
                append(line)
            }
        }
        guard !transactions.isEmpty else { throw ParseError.empty }
        return ParsedDocument(source: .idfc, declaredPeriod: declaredPeriod, transactions: transactions)
    }

    /// Deterministic identity for rows without a rail reference. The resulting
    /// balance is identical across the PDF and XLSX renditions of a statement
    /// (whose narrations differ by truncation), so dual-format imports dedup.
    /// Never collides with real UPI/NEFT refs (distinct shape).
    static func syntheticReference(balancePaise: Int64, date: Date, amountPaise: Int64) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "B\(balancePaise)D\(formatter.string(from: date))A\(amountPaise)"
    }

    /// Counterparty/reference from the particulars, by transaction rail:
    /// "UPI/DR/<ref>/<name>/…", "NEFT/<ref>/<name>/…", "POS-…/<name>/<ref>/…".
    static func extract(from particulars: String) -> (counterparty: String, reference: String?) {
        let parts = particulars.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 4, parts[0] == "UPI", parts[1] == "DR" || parts[1] == "CR" {
            return (parts[3], parts[2].isEmpty ? nil : parts[2])
        }
        if parts.count >= 3, parts[0] == "NEFT" || parts[0] == "IMPS" || parts[0] == "RTGS" {
            return (parts[2], parts[1].isEmpty ? nil : parts[1])
        }
        if parts.count >= 3, parts[0].hasPrefix("POS") {
            let ref = parts[2].allSatisfy(\.isNumber) && !parts[2].isEmpty ? parts[2] : nil
            return (parts[1], ref)
        }
        let name = String(particulars.prefix(60)).trimmingCharacters(in: .whitespaces)
        return (name, nil)
    }
}

#if canImport(PDFKit)
public struct IDFCPDFParser: StatementParser {
    public let source = Source.idfc

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: Array("%PDF".utf8)) else { return false }
        guard let doc = PDFDocument(data: data) else { return false }
        if doc.isLocked {
            return filename.uppercased().contains("IDFC")
        }
        guard let text = doc.page(at: 0)?.string else { return false }
        return text.contains("STATEMENT OF ACCOUNT") && text.contains("IDFC FIRST BANK")
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let doc = PDFDocument(data: data) else { throw ParseError.unrecognizedFormat }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw ParseError.passwordRequired
            }
        }
        let pages = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }
        return try IDFCStatementText.parse(pages: pages)
    }
}
#endif
