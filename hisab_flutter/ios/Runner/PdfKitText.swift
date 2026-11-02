import Flutter
import PDFKit

/// PDFKit's positioned text for a statement PDF, for Dart's table rebuilder
/// (hisab_core's StatementLayout). On iOS this replaces Syncfusion, which
/// drops glyphs in some embedded fonts (IDFC FIRST's among them) and so
/// corrupts references; PDFKit is what the Swift app read every PDF with.
///
/// Returns raw line runs and, for a run that is one text range, each word's
/// x-extent. Deciding where to cut a run (the Swift app's
/// NormalizedTable.split) happens in Dart, so the rule lives in one place.
enum PdfKitText {
    static func register(with messenger: FlutterBinaryMessenger) {
        FlutterMethodChannel(name: "hisab/pdfkit", binaryMessenger: messenger)
            .setMethodCallHandler { call, result in
                guard call.method == "pages",
                      let args = call.arguments as? [String: Any],
                      let data = (args["data"] as? FlutterStandardTypedData)?.data else {
                    return result(FlutterMethodNotImplemented)
                }
                let password = args["password"] as? String
                DispatchQueue.global(qos: .userInitiated).async {
                    let pages = read(data, password: password)
                    DispatchQueue.main.async { result(pages) }
                }
            }
    }

    /// nil when the PDF cannot be opened or stays locked.
    private static func read(_ data: Data, password: String?) -> [[[String: Any]]]? {
        guard let doc = PDFDocument(data: data) else { return nil }
        if doc.isLocked, !(password.map { doc.unlock(withPassword: $0) } ?? false) { return nil }
        return (0..<doc.pageCount).map { index in
            guard let page = doc.page(at: index),
                  let selection = page.selection(for: page.bounds(for: .mediaBox)) else { return [] }
            let text = (page.string ?? "") as NSString
            return selection.selectionsByLine().map { run(run: $0, on: page, text: text) }
        }
    }

    private static func run(run: PDFSelection, on page: PDFPage, text: NSString) -> [String: Any] {
        let b = run.bounds(for: page)
        var out: [String: Any] = ["t": run.string ?? "", "x0": b.minX, "x1": b.maxX, "y0": b.minY, "y1": b.maxY]
        guard run.numberOfTextRanges(on: page) == 1 else { return out }
        let range = run.range(at: 0, on: page)
        guard range.location != NSNotFound, NSMaxRange(range) <= text.length else { return out }
        let words = text.substring(with: range).split(separator: " ", omittingEmptySubsequences: false)
        guard words.count > 1 else { return out }
        var offset = range.location
        var measured: [[String: Any]] = []
        for word in words {
            let length = (String(word) as NSString).length
            defer { offset += length + 1 }
            guard length > 0,
                  let w = page.selection(for: NSRange(location: offset, length: length)) else { continue }
            let wb = w.bounds(for: page)
            measured.append(["t": word.trimmingCharacters(in: .whitespacesAndNewlines), "x0": wb.minX, "x1": wb.maxX])
        }
        out["words"] = measured
        return out
    }
}
