import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// One logical row of an HDFC "Statement of account" table, as reassembled from the
/// PDF's geometry (the raw text stream scrambles columns beyond line-based repair).
public struct HDFCRow {
    public var dateText: String?
    public var narration: String
    public var refText: String?
    public var withdrawalText: String?
    public var depositText: String?
    public var balanceText: String?

    public init(dateText: String? = nil, narration: String = "", refText: String? = nil,
                withdrawalText: String? = nil, depositText: String? = nil, balanceText: String? = nil) {
        self.dateText = dateText
        self.narration = narration
        self.refText = refText
        self.withdrawalText = withdrawalText
        self.depositText = depositText
        self.balanceText = balanceText
    }
}

/// Pure table-semantics layer: direction from which amount column is filled,
/// verified against the running Closing Balance chain; HDFC's zero-padded
/// reference numbers normalized (leading zeros stripped) so they match the
/// UPI transaction IDs that GPay/Paytm statements carry.
public enum HDFCStatementTable {
    public static func parse(rows: [HDFCRow], openingBalancePaise: Int64?,
                             period: DatePeriod?) throws -> ParsedDocument {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = YearMonth.istCalendar
        dateFormatter.timeZone = YearMonth.istCalendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd/MM/yy"

        var previousBalance = openingBalancePaise
        var transactions: [ParsedTransaction] = []

        for row in rows {
            guard let dateText = row.dateText, let date = dateFormatter.date(from: dateText),
                  let balanceText = row.balanceText,
                  let balance = Money.signedPaise(fromDecimalString: balanceText) else {
                throw ParseError.malformedRow(0, row.narration)
            }
            let withdrawal = row.withdrawalText.flatMap(Money.signedPaise(fromDecimalString:))
            let deposit = row.depositText.flatMap(Money.signedPaise(fromDecimalString:))
            let direction: Direction
            let amount: Int64
            switch (withdrawal, deposit) {
            case (let w?, nil): direction = .debit; amount = w
            case (nil, let d?): direction = .credit; amount = d
            default: throw ParseError.malformedRow(0, "amount columns ambiguous: \(row.narration)")
            }
            if let previous = previousBalance {
                let expected = direction == .debit ? previous - amount : previous + amount
                guard expected == balance else {
                    throw ParseError.malformedRow(0, "balance chain break at: \(row.narration) "
                        + "[date=\(row.dateText ?? "-") w=\(row.withdrawalText ?? "-") "
                        + "d=\(row.depositText ?? "-") bal=\(row.balanceText ?? "-") prev=\(previous)]")
                }
            }
            previousBalance = balance

            let narration = row.narration.trimmingCharacters(in: .whitespaces)
            let reference = Self.normalizedReference(row.refText)
                ?? IDFCStatementText.syntheticReference(balancePaise: balance, date: date,
                                                        amountPaise: amount)
            transactions.append(ParsedTransaction(
                date: date, amountPaise: amount, direction: direction,
                counterparty: Self.counterparty(from: narration),
                reference: reference, narration: narration))
        }
        guard !transactions.isEmpty else { throw ParseError.empty }
        return ParsedDocument(source: .hdfc, declaredPeriod: period, transactions: transactions)
    }

    /// "0000102422789385" -> "102422789385"; all zeros / empty -> nil.
    static func normalizedReference(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.drop { $0 == "0" }
        return stripped.isEmpty ? nil : String(stripped)
    }

    /// "UPI-<NAME>-<vpa>-…" -> NAME; "NEFT CR-<ifsc>-<NAME>-…" -> NAME; else the narration.
    static func counterparty(from narration: String) -> String {
        let parts = narration.split(separator: "-", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 2, parts[0] == "UPI" {
            return parts[1]
        }
        if parts.count >= 3, ["NEFT CR", "NEFT DR", "IMPS", "RTGS CR", "RTGS DR", "ACH C", "ACH D"].contains(parts[0]) {
            return parts[2]
        }
        return String(narration.prefix(60))
    }
}

#if canImport(PDFKit)
/// Geometric extractor: rebuilds the table from per-character bounds, since HDFC's
/// PDF text stream interleaves whole columns. Words are clustered into visual lines
/// by Y, assigned to columns by the header row's X positions, and merged into
/// logical rows (a row starts where the Date column holds a dd/MM/yy value).
public struct HDFCPDFParser: StatementParser {
    public let source = Source.hdfc

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: Array("%PDF".utf8)) else { return false }
        guard let doc = PDFDocument(data: data) else { return false }
        if doc.isLocked {
            let name = filename.lowercased()
            return name.contains("hdfc") || name.contains("acct statement")
        }
        guard let text = doc.page(at: 0)?.string else { return false }
        return text.contains("Statement of account") && text.contains("HDFC BANK")
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        guard let doc = PDFDocument(data: data) else { throw ParseError.unrecognizedFormat }
        if doc.isLocked {
            guard let password, doc.unlock(withPassword: password) else {
                throw ParseError.passwordRequired
            }
        }

        // Column geometry from the page-1 header via findString (rect selections are
        // reliable on these PDFs; the raw reading order and characterBounds are not).
        // The layout is identical on every page, so it is measured once and reused.
        func headerX(_ title: String) -> CGFloat? {
            guard let sel = doc.findString(title, withOptions: []).first,
                  let page = sel.pages.first else { return nil }
            return sel.bounds(for: page).minX
        }
        guard let narrationX = headerX("Narration"),
              let refX = headerX("Chq./Ref.No."),
              let valueDtX = headerX("Value Dt"),
              let withdrawalX = headerX("Withdrawal Amt."),
              let depositX = headerX("Deposit Amt."),
              let closingX = headerX("Closing Balance"),
              let headerSel = doc.findString("Narration", withOptions: []).first,
              let headerPage = headerSel.pages.first else {
            throw ParseError.unrecognizedFormat
        }
        let headerY = headerSel.bounds(for: headerPage).minY
        let summarySelection = doc.findString("STATEMENT SUMMARY", withOptions: []).first
        // Pages after the first repeat the account block but NOT the column header;
        // their rows start higher. The per-page table top hangs off the repeated
        // "Statement of account" label instead.
        let labelSelections = doc.findString("Statement of account", withOptions: [])
        _ = narrationX  // narration's left edge is derived from data, not the centered title

        var fullText = ""
        var rows: [HDFCRow] = []
        var open: HDFCRow?

        for pageIndex in 0..<doc.pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            fullText += (page.string ?? "") + "\n"
            let pageBounds = page.bounds(for: .mediaBox)

            var tableTop = labelSelections.first { $0.pages.contains(page) }
                .map { $0.bounds(for: page).minY - 2 } ?? 613
            if headerSel.pages.contains(page) {
                tableTop = min(tableTop, headerY - 2)
            }

            // Row anchors: transaction-date runs (dd/MM/yy) in the leftmost column.
            guard let pageSelection = page.selection(for: pageBounds) else { continue }
            var anchors: [(y: CGFloat, maxX: CGFloat)] = []
            for run in pageSelection.selectionsByLine() {
                let text = (run.string ?? "").trimmingCharacters(in: .whitespaces)
                let bounds = run.bounds(for: page)
                if bounds.minX < 150, bounds.minY < tableTop,
                   text.wholeMatch(of: #/\d{2}/\d{2}/\d{2}/#) != nil {
                    anchors.append((bounds.minY, bounds.maxX))
                }
            }
            anchors.sort { $0.y > $1.y }
            guard !anchors.isEmpty else { continue }

            let dateRight = anchors.map(\.maxX).max()! + 3
            var tableBottom: CGFloat = 40
            if let summary = summarySelection, summary.pages.contains(page) {
                tableBottom = summary.bounds(for: page).maxY + 2
            }

            func bandText(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) -> String {
                let rect = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
                guard let selection = page.selection(for: rect) else { return "" }
                let lines = selection.selectionsByLine()
                    .sorted { $0.bounds(for: page).minY > $1.bounds(for: page).minY }
                    .compactMap { $0.string?.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !Self.isFooter($0) }
                return lines.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            }

            // Narration spilling above this page's first anchor belongs to the row
            // carried over from the previous page.
            if open != nil {
                let spill = bandText(left: dateRight, right: refX - 4,
                                     top: tableTop, bottom: anchors[0].y + 9)
                if !spill.isEmpty {
                    open!.narration += (open!.narration.isEmpty ? "" : " ") + spill
                }
            }

            for (index, anchor) in anchors.enumerated() {
                if let finished = open { rows.append(finished) }
                let top = anchor.y + 9
                let bottom = index + 1 < anchors.count ? anchors[index + 1].y + 9 : tableBottom

                var row = HDFCRow(dateText: bandText(left: 0, right: dateRight,
                                                     top: top, bottom: anchor.y - 1))
                row.narration = bandText(left: dateRight, right: refX - 4, top: top, bottom: bottom)
                let ref = bandText(left: refX - 4, right: valueDtX - 4, top: top, bottom: bottom)
                row.refText = ref.isEmpty ? nil : String(ref.split(separator: " ").first ?? "")
                let w = bandText(left: withdrawalX - 8, right: depositX - 8, top: top, bottom: bottom)
                row.withdrawalText = w.isEmpty ? nil : w
                let d = bandText(left: depositX - 8, right: closingX - 8, top: top, bottom: bottom)
                row.depositText = d.isEmpty ? nil : d
                let b = bandText(left: closingX - 8, right: pageBounds.width, top: top, bottom: bottom)
                row.balanceText = b.isEmpty ? nil : String(b.split(separator: " ").first ?? "")
                open = row
            }

            if summarySelection?.pages.contains(page) == true { break }
        }
        if let finished = open { rows.append(finished) }

        return try HDFCStatementTable.parse(
            rows: rows,
            openingBalancePaise: Self.openingBalance(in: fullText),
            period: Self.period(in: fullText))
    }

    static func isFooter(_ text: String) -> Bool {
        text.contains("HDFC BANK LIMITED")
            || text.contains("Closing balance includes")
            || text.contains("Contents of this statement")
            || text.contains("GSTN") || text.contains("GSTIN")
            || text.contains("Registered Office Address")
            || text.contains("Page No")
            || text.contains("computer generated statement")
    }

    static func period(in text: String) -> DatePeriod? {
        guard let match = text.firstMatch(of: #/From : (\d{2}/\d{2}/\d{4})\s+To : (\d{2}/\d{2}/\d{4})/#) else {
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

    /// From "STATEMENT SUMMARY :- … 10,055.58 414 37 …" — first number after the header.
    static func openingBalance(in text: String) -> Int64? {
        guard let match = text.firstMatch(of: #/STATEMENT SUMMARY :-\s*\n[^\n]*\n([\d,]+\.\d{2}) /#) else {
            return nil
        }
        return Money.signedPaise(fromDecimalString: String(match.1))
    }
}
#endif
