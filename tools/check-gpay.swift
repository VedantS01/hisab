// Validates GPayPDFParser against a real statement (not committed).
// Usage: swift tools/check-gpay.swift <statement.pdf> [password]
// Build note: run via `swift run` context or compile with HisabCore sources:
//   swiftc tools/check-gpay.swift HisabCore/Sources/HisabCore/*.swift -o /tmp/check-gpay
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("usage: check-gpay.swift <pdf> [password]") }
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let parser = GPayPDFParser()
print("canParse:", parser.canParse(data: data, filename: (args[1] as NSString).lastPathComponent))
let doc = try parser.parse(data: data, password: args.count >= 3 ? args[2] : nil)
let debits = doc.transactions.filter { $0.direction == .debit }
let credits = doc.transactions.filter { $0.direction == .credit }
let debitSum = debits.reduce(Int64(0)) { $0 + $1.amountPaise }
let creditSum = credits.reduce(Int64(0)) { $0 + $1.amountPaise }
print("transactions:", doc.transactions.count)
print("debits:", debits.count, "sum:", Money.formatPaise(debitSum))
print("credits:", credits.count, "sum:", Money.formatPaise(creditSum))
print("declaredPeriod months:", doc.declaredPeriod?.months.map(\.description) ?? [])
print("refs unique:", Set(doc.transactions.compactMap(\.reference)).count)
let noRef = doc.transactions.filter { $0.reference == nil }.count
print("missing refs:", noRef)
