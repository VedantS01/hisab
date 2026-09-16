import XCTest
@testable import HisabCore

/// Machine-verification of every bundled spec: each must validate its own
/// synthetic fixture and never cross-detect another spec's fixture.
final class BundledSpecTests: XCTestCase {
    func testEveryBundledSpecValidatesItsFixtureAndOnlyItsFixture() throws {
        let specs = SpecStore.bundled()
        XCTAssertGreaterThanOrEqual(specs.count, 9)  // 8 banks + idfc-xlsx

        for spec in specs where spec.id != "idfc-xlsx" {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "\(spec.id)-fixture",
                                                      withExtension: "csv",
                                                      subdirectory: "Fixtures"),
                                    "missing fixture for \(spec.id)")
            let data = try Data(contentsOf: url)
            let table = try XCTUnwrap(NormalizedTable.from(data: data, filename: "f.csv",
                                                           password: nil))
            guard case .validated(let txns)? = SpecExecutor.execute(table: table, spec: spec) else {
                return XCTFail("\(spec.id) failed its own fixture")
            }
            XCTAssertGreaterThanOrEqual(txns.count, 10, spec.id)

            for other in specs where other.id != spec.id {
                let outcome = SpecExecutor.execute(table: table, spec: other)
                XCTAssertNil(outcome, "\(other.id) cross-detected \(spec.id)'s fixture")
            }
        }
    }

    func testBundledSpecHygiene() {
        let specs = SpecStore.bundled()
        XCTAssertEqual(Set(specs.map(\.id)).count, specs.count, "duplicate spec ids")
        for spec in specs {
            XCTAssertTrue(spec.sourceID == "idfc" || spec.sourceID.hasPrefix("bank:"), spec.id)
            XCTAssertFalse(spec.dateFormats.isEmpty, spec.id)
            XCTAssertTrue(["debitCredit", "signedAmount", "amountDRCR", "unsignedChain"]
                .contains(spec.signConvention), spec.id)
        }
    }
}
