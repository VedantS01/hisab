import Foundation

/// Parser for Paytm "UPI Statement" .xlsx exports. One sheet is a summary (carries the
/// "5 MAR'26 - 4 SEP'26" period); another holds the transaction table with headers:
/// Date | Time | Transaction Details | Other Transaction Details (UPI ID or A/c No) |
/// Your Account | Amount | UPI Ref No. | Order ID | Remarks | Tags | Comment
/// Amounts are signed strings ("-453.00" paid, "+600.00" received).
public struct PaytmXLSXParser: StatementParser {
    public let source = Source.paytm

    public init() {}

    public func canParse(data: Data, filename: String) -> Bool {
        guard data.starts(with: [0x50, 0x4B]) else { return false }
        guard let workbook = try? XLSXReader.read(data: data) else { return false }
        return workbook.sharedStrings.contains { $0.contains("Paytm Statement for") }
    }

    public func parse(data: Data, password: String?) throws -> ParsedDocument {
        let workbook: XLSXReader.Workbook
        do {
            workbook = try XLSXReader.read(data: data)
        } catch {
            throw ParseError.unrecognizedFormat
        }

        guard let table = workbook.sheets.values.first(where: { rows in
            guard let header = rows.first else { return false }
            return header["A"] == "Date" && header["B"] == "Time"
        }) else { throw ParseError.unrecognizedFormat }

        let header = table[0]
        func column(startingWith title: String) -> String? {
            header.first { $0.value.hasPrefix(title) }?.key
        }
        guard let dateCol = column(startingWith: "Date"),
              let timeCol = column(startingWith: "Time"),
              let detailCol = column(startingWith: "Transaction Details"),
              let amountCol = column(startingWith: "Amount") else {
            throw ParseError.unrecognizedFormat
        }
        let refCol = column(startingWith: "UPI Ref")
        let accountCol = column(startingWith: "Your Account")
        let otherCol = column(startingWith: "Other Transaction")
        let tagsCol = column(startingWith: "Tags")
        let remarksCol = column(startingWith: "Remarks")

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = YearMonth.istCalendar
        dateFormatter.timeZone = YearMonth.istCalendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd/MM/yyyy HH:mm:ss"

        var transactions: [ParsedTransaction] = []
        for (index, row) in table.dropFirst().enumerated() {
            let rowNo = index + 2
            if row.isEmpty { continue }
            guard let dateText = row[dateCol], let timeText = row[timeCol],
                  let date = dateFormatter.date(from: "\(dateText) \(timeText)"),
                  let amountText = row[amountCol],
                  let signedPaise = Money.signedPaise(fromDecimalString: amountText),
                  signedPaise != 0,
                  let detail = row[detailCol] else {
                throw ParseError.malformedRow(rowNo, row.sorted(by: { $0.key < $1.key })
                    .map(\.value).joined(separator: ","))
            }

            var counterparty = detail
            for prefix in ["Paid to ", "Received from ", "Money sent to "] where detail.hasPrefix(prefix) {
                counterparty = String(detail.dropFirst(prefix.count))
                break
            }

            var narrationParts = [detail]
            if let other = otherCol.flatMap({ row[$0] }) { narrationParts.append(other) }
            if let account = accountCol.flatMap({ row[$0] }) { narrationParts.append(account) }
            if let remarks = remarksCol.flatMap({ row[$0] }) { narrationParts.append(remarks) }
            if let tags = tagsCol.flatMap({ row[$0] }) { narrationParts.append(tags) }

            transactions.append(ParsedTransaction(
                date: date,
                amountPaise: abs(signedPaise),
                direction: signedPaise < 0 ? .debit : .credit,
                counterparty: counterparty,
                reference: refCol.flatMap { row[$0] },
                narration: narrationParts.joined(separator: " / ")))
        }
        guard !transactions.isEmpty else { throw ParseError.empty }

        return ParsedDocument(source: .paytm,
                              declaredPeriod: Self.period(in: workbook.sharedStrings),
                              transactions: transactions)
    }

    /// Finds "5 MAR'26 - 4 SEP'26" anywhere in the workbook's strings.
    static func period(in strings: [String]) -> DatePeriod? {
        let months = ["JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
                      "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12]
        let regex = /^(\d{1,2}) ([A-Z]{3})'(\d{2}) - (\d{1,2}) ([A-Z]{3})'(\d{2})$/
        for raw in strings {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard let match = text.wholeMatch(of: regex),
                  let startMonth = months[String(match.2)], let endMonth = months[String(match.5)],
                  let startDay = Int(match.1), let endDay = Int(match.4),
                  let startYear = Int(match.3), let endYear = Int(match.6) else { continue }
            let cal = YearMonth.istCalendar
            guard let start = cal.date(from: DateComponents(year: 2000 + startYear, month: startMonth,
                                                            day: startDay, hour: 0)),
                  let end = cal.date(from: DateComponents(year: 2000 + endYear, month: endMonth,
                                                          day: endDay, hour: 23, minute: 59)) else { continue }
            return DatePeriod(start: start, end: end)
        }
        return nil
    }
}
