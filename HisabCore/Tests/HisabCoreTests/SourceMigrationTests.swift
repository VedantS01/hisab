import XCTest
@testable import HisabCore

/// Guards the Source open-id migration: these hashes were computed with the
/// original closed `Source` enum and must never change. If this test fails,
/// stored transactions on users' devices would duplicate on reimport.
final class SourceMigrationTests: XCTestCase {
    private func txn(ref: String?, narration: String = "UPI/PAY/x") -> ParsedTransaction {
        ParsedTransaction(date: Date(timeIntervalSince1970: 1_772_600_000),
                          amountPaise: 12_345,
                          direction: .debit,
                          counterparty: "BLUE TOKAI",
                          reference: ref,
                          narration: narration)
    }

    func testRefKeyedHashesArePinned() {
        XCTAssertEqual(txn(ref: "425100012345").contentHash(source: .gpay),
                       "532f81e564fa279187375979347d870a9e9fc0936d5e7d9e31c22c8d9399b059")
        XCTAssertEqual(txn(ref: "425100012345").contentHash(source: .paytm),
                       "10f9d2d950eb1553fe9bb45d031f76fdc1c13eec0a31a371dca262f41d14c50c")
        XCTAssertEqual(txn(ref: "425100012345").contentHash(source: .bhim),
                       "241b83db79cd8ca0eaf1da18dde8a76ff378bb004eb5ef83a0769e3b78aea719")
        XCTAssertEqual(txn(ref: "425100012345").contentHash(source: .hdfc),
                       "962aaa86d8f4760633d7348644933fe7b30c028b4143580a1e47dbb0b3238bd6")
        XCTAssertEqual(txn(ref: "425100012345").contentHash(source: .idfc),
                       "219b6e9795333ecb2b41ab73ec0cadcc8ac1cb2387fb8194b7a20ac2535e520a")
    }

    func testRefLessFallbackHashIsPinned() {
        XCTAssertEqual(txn(ref: nil, narration: "  POS   1234  Coffee ").contentHash(source: .hdfc),
                       "a756f6fc0f7b272b2983b46c0a7855aba0d3adfed7de4e9809d8943ddba4657d")
    }

    func testOpenSourceIDs() {
        let sbi = Source(rawValue: "bank:sbi")
        XCTAssertEqual(sbi.kind, .bank)
        XCTAssertEqual(sbi.displayName, "SBI")
        let phonepe = Source(rawValue: "upi:phonepe")
        XCTAssertEqual(phonepe.kind, .paymentApp)
        XCTAssertEqual(phonepe.displayName, "Phonepe")
        XCTAssertEqual(Source(rawValue: "hdfc"), Source.hdfc)
        XCTAssertEqual(Source.builtIn, [.gpay, .paytm, .bhim, .hdfc, .idfc])
        // Codable stays a bare string, exactly like the old enum.
        let encoded = try! JSONEncoder().encode([Source.hdfc, sbi])
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["hdfc","bank:sbi"]"#)
        let decoded = try! JSONDecoder().decode([Source].self, from: encoded)
        XCTAssertEqual(decoded, [.hdfc, sbi])
    }

    func testCanonicalRawValuesAreFrozen() {
        XCTAssertEqual(Source.gpay.rawValue, "gpay")
        XCTAssertEqual(Source.paytm.rawValue, "paytm")
        XCTAssertEqual(Source.bhim.rawValue, "bhim")
        XCTAssertEqual(Source.hdfc.rawValue, "hdfc")
        XCTAssertEqual(Source.idfc.rawValue, "idfc")
    }
}
