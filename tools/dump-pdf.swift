// Dumps a PDF's per-page text exactly as PDFKit extracts it (what the app's
// parsers see). Usage: swift tools/dump-pdf.swift <file.pdf> [password] [maxPages]
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count >= 2, let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    fatalError("usage: dump-pdf.swift <file.pdf> [password] [maxPages]")
}
if doc.isLocked {
    guard args.count >= 3, doc.unlock(withPassword: args[2]) else {
        print("LOCKED: password required or wrong")
        exit(2)
    }
}
let maxPages = args.count >= 4 ? Int(args[3])! : doc.pageCount
print("pages=\(doc.pageCount) locked=\(doc.isLocked)")
for index in 0..<min(maxPages, doc.pageCount) {
    print("===== PAGE \(index + 1) =====")
    print(doc.page(at: index)?.string ?? "<no text>")
}
