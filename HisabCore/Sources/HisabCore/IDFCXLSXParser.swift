import Foundation

/// Parser for IDFC FIRST Bank .xlsx statements. Unlike the PDF rendition, the sheet
/// has explicit Debit/Credit numeric columns; the running Balance column is still
/// verified so a misread row throws instead of miscounting. Ref-less rows get the
/// same balance-keyed synthetic reference as the PDF parser, so importing both
/// renditions of one statement dedups completely.
public struct IDFCXLSXParser: StatementParser {
    public let source = Source.idfc

    public init() {}

    private static var periodRegex: Regex<(Substring, Substring, Substring)> {
        /^(\d{2}-[A-Za-z]{3}-\d{4}) TO (\d{2}-[A-Za-z]{3}-\d{4})$/
    }

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: [0x50, 0x4B]) else { return false }
        guard let workbook = try? XLSXReader.read(data: data) else { return false }
        return workbook.sharedStrings.contains("STATEMENT OF ACCOUNT")
            && workbook.sharedStrings.contains { $0.hasPrefix("IDFB") }
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        let workbook: XLSXReader.Workbook
        do {
            workbook = try XLSXReader.read(data: data)
        } catch {
            throw ParseError.unrecognizedFormat
        }

        guard let rows = workbook.sheets.values.first(where: { sheet in
            sheet.contains { $0.values.contains("Transaction Date") }
        }) else { throw ParseError.unrecognizedFormat }
        guard let headerIndex = rows.firstIndex(where: { $0.values.contains("Transaction Date") }) else {
            throw ParseError.unrecognizedFormat
        }
        let header = rows[headerIndex]
        func column(_ title: String) -> String? { header.first { $0.value == title }?.key }
        guard let dateCol = column("Transaction Date"),
              let particularsCol = column("Particulars"),
              let debitCol = column("Debit"),
              let creditCol = column("Credit"),
              let balanceCol = column("Balance") else {
            throw ParseError.unrecognizedFormat
        }

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = YearMonth.istCalendar
        dateFormatter.timeZone = YearMonth.istCalendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd-MMM-yyyy"

        var previousBalance: Int64?
        var transactions: [ParsedTransaction] = []

        for row in rows.dropFirst(headerIndex + 1) {
            guard let dateText = row[dateCol], let date = dateFormatter.date(from: dateText),
                  let particulars = row[particularsCol],
                  let balanceText = row[balanceCol],
                  let balance = Self.paise(fromNumericCell: balanceText) else { continue }

            let debit = row[debitCol].flatMap(Self.paise(fromNumericCell:))
            let credit = row[creditCol].flatMap(Self.paise(fromNumericCell:))
            let direction: Direction
            let amount: Int64
            switch (debit, credit) {
            case (let d?, nil): direction = .debit; amount = d
            case (nil, let c?): direction = .credit; amount = c
            default: throw ParseError.malformedRow(0, particulars)
            }

            if let previous = previousBalance {
                let expected = direction == .debit ? previous - amount : previous + amount
                guard expected == balance else {
                    throw ParseError.malformedRow(0, "balance chain break at: \(particulars)")
                }
            }
            previousBalance = balance

            let (counterparty, reference) = IDFCStatementText.extract(from: particulars)
            transactions.append(ParsedTransaction(
                date: date, amountPaise: amount, direction: direction,
                counterparty: counterparty,
                reference: reference ?? IDFCStatementText.syntheticReference(
                    balancePaise: balance, date: date, amountPaise: amount),
                narration: particulars))
        }
        guard !transactions.isEmpty else { throw ParseError.empty }

        var declaredPeriod: DatePeriod?
        for text in workbook.sharedStrings {
            guard let match = text.wholeMatch(of: Self.periodRegex),
                  let start = dateFormatter.date(from: String(match.1)),
                  let end = dateFormatter.date(from: String(match.2)) else { continue }
            declaredPeriod = DatePeriod(start: start, end: end)
            break
        }
        return ParsedDocument(source: .idfc, declaredPeriod: declaredPeriod, transactions: transactions)
    }

    /// "303594.0" / "1417816.76" / "1999" -> paise, exact via Decimal.
    static func paise(fromNumericCell raw: String) -> Int64? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        var scaled = value * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return (rounded as NSDecimalNumber).int64Value
    }
}
