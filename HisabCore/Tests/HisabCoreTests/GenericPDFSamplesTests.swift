import XCTest
@testable import HisabCore

/// Reads the real bank PDFs in the gitignored samples/ directory through the
/// generic path alone (no dedicated parser, no spec) and checks it lands on
/// exactly what the dedicated parser reads. Gated on SAMPLES_DIR so CI, which
/// has no samples, skips it.
final class GenericPDFSamplesTests: XCTestCase {
    static let files = [
        "hdfc/Acct Statement_3293_23062026_13.38.47.pdf": "135244908",
        "idfc/IDFCFIRSTBankstatement_10061308816.pdf": nil,
    ] as [String: String?]

    func testGenericPathMatchesDedicatedParsers() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SAMPLES_DIR"] else {
            throw XCTSkip("SAMPLES_DIR not set")
        }
        let generic = ImportResolver(registry: ParserRegistry(parsers: []), specs: [])
        for (file, password) in Self.files.sorted(by: { $0.key < $1.key }) {
            let data = try Data(contentsOf: URL(fileURLWithPath: "\(dir)/\(file)"))
            let name = (file as NSString).lastPathComponent
            let expected = try XCTUnwrap(ParserRegistry.live.detect(data: data, filename: name))
                .parse(data: data, password: password)

            guard case .parsed(let doc) = generic.resolve(data: data, filename: name, password: password) else {
                let table = NormalizedTable.from(data: data, filename: name, password: password)
                XCTFail("\(file): generic path refused; table \(table?.rows.count ?? 0) rows: "
                    + "\(table?.rows.prefix(6).map { $0.joined(separator: " | ") } ?? [])")
                continue
            }
            func key(_ t: ParsedTransaction) -> String { "\(t.date.timeIntervalSince1970) \(t.amountPaise) \(t.direction)" }
            XCTAssertEqual(doc.transactions.map(key).sorted(), expected.transactions.map(key).sorted(), file)
            // Narrations agree up to whitespace where wrapped lines are joined,
            // and up to a tail one side drops: IDFCParser loses the part of a
            // narration that runs onto the next page, the layout reader moves a
            // cheque number into its own column. HDFCPDFParser's page-break
            // bands clip footer text into the row ("…ANK LIMITED lance
            // includes funds…"), so those rows can't agree.
            func letters(_ t: ParsedTransaction) -> String { t.narration.filter { !$0.isWhitespace } }
            let read = Dictionary(grouping: doc.transactions, by: key)
            let differ = expected.transactions.filter { want in
                !want.narration.contains("lance includes") && !(read[key(want)] ?? []).contains { got in
                    letters(got).hasPrefix(letters(want)) || letters(want).hasPrefix(letters(got))
                }
            }
            XCTAssert(differ.isEmpty, "\(file): narrations differ:\n" + differ.prefix(5).map(\.narration).joined(separator: "\n"))

            // The on-device model, shown the same table, must name columns
            // under which the chain closes on the same transactions.
            #if canImport(FoundationModels)
            if ProcessInfo.processInfo.environment["HISAB_LIVE_MODEL"] != nil, #available(macOS 26, iOS 26, *),
               OnDeviceColumnReader.isAvailable,
               let table = NormalizedTable.from(data: data, filename: name, password: password) {
                let read = await ProposedMapping.read(table: table, proposer: OnDeviceColumnReader())
                XCTAssertEqual(read?.transactions.map(key).sorted(), expected.transactions.map(key).sorted(), "\(file) via model")
            }
            #endif
        }
    }
}
