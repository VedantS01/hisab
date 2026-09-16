import XCTest
@testable import HisabCore

/// The proving case for the generic engine: a bundled spec must reproduce the
/// hand-written IDFC XLSX parser hash-for-hash on the same fixture. If this
/// holds, a spec-parsed statement dedups perfectly against a code-parsed one.
final class SpecParityTests: XCTestCase {
    func testIDFCXLSXSpecMatchesCodeParserHashes() throws {
        let url = Bundle.module.url(forResource: "idfc-fixture", withExtension: "xlsx",
                                    subdirectory: "Fixtures")!
        let data = try Data(contentsOf: url)

        let legacy = try IDFCXLSXParser().parse(data: data, password: nil)
        let table = NormalizedTable.from(data: data, filename: "statement.xlsx", password: nil)!
        guard let spec = SpecStore.bundled().first(where: { $0.id == "idfc-xlsx" }) else {
            return XCTFail("idfc-xlsx spec missing from bundle")
        }
        guard case .validated(let txns)? = SpecExecutor.execute(table: table, spec: spec) else {
            return XCTFail("spec did not validate the fixture")
        }

        XCTAssertEqual(txns.count, legacy.transactions.count)
        let legacyHashes = Set(legacy.transactions.map { $0.contentHash(source: .idfc) })
        let specHashes = Set(txns.map { $0.contentHash(source: Source(rawValue: spec.sourceID)) })
        XCTAssertEqual(specHashes, legacyHashes)
    }
}
