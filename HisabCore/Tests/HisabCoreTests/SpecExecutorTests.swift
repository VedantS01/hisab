import XCTest
@testable import HisabCore

final class SpecExecutorTests: XCTestCase {
    private let sbiLikeSpec = FormatSpec(
        id: "test-sbi",
        sourceID: "bank:sbi",
        bankName: "State Bank of India",
        headerPatterns: ["date": "^txn date$",
                         "narration": "^description$",
                         "reference": "ref no",
                         "debit": "^debit$",
                         "credit": "^credit$",
                         "balance": "^balance$"],
        furniturePatterns: ["statement of account"],
        dateFormats: ["dd/MM/yyyy"],
        signConvention: "debitCredit")

    private var sbiLikeTable: NormalizedTable {
        NormalizedTable(rows: [
            ["STATE BANK OF INDIA"],
            ["Statement of Account"],
            ["Txn Date", "Description", "Ref No./Cheque No.", "Debit", "Credit", "Balance"],
            ["01/04/2026", "POS COFFEE", "R1", "100.00", "", "900.00"],
            ["02/04/2026", "SALARY CREDIT", "R2", "", "50.00", "950.00"],
            ["03/04/2026", "UPI GROCER", "R3", "200.00", "", "750.00"],
        ], container: "csv")
    }

    func testSpecValidatesMatchingTable() {
        guard case .validated(let txns)? = SpecExecutor.execute(table: sbiLikeTable,
                                                                spec: sbiLikeSpec) else {
            return XCTFail("expected validation")
        }
        XCTAssertEqual(txns.count, 3)
        XCTAssertEqual(txns.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual(txns[0].reference, "R1")
    }

    func testSpecReturnsNilOnForeignTable() {
        let paytmish = NormalizedTable(rows: [
            ["Date", "Transaction Details", "Amount"],
            ["01/04/2026", "Paid to X", "-100"],
        ], container: "csv")
        XCTAssertNil(SpecExecutor.execute(table: paytmish, spec: sbiLikeSpec))
    }

    func testTamperedBalanceIsBroken() {
        var table = sbiLikeTable
        table.rows[4][5] = "999.00"
        guard case .broken? = SpecExecutor.execute(table: table, spec: sbiLikeSpec) else {
            return XCTFail("expected broken chain")
        }
    }

    func testFurnitureRowsAreStripped() {
        var table = sbiLikeTable
        table.rows.insert(["Statement of Account contd."], at: 4)
        guard case .validated(let txns)? = SpecExecutor.execute(table: table, spec: sbiLikeSpec) else {
            return XCTFail("expected validation with furniture stripped")
        }
        XCTAssertEqual(txns.count, 3)
    }

    func testBundledSpecsDecode() {
        // May be empty until specs land; must never crash or mis-decode.
        for spec in SpecStore.bundled() {
            XCTAssertFalse(spec.id.isEmpty)
            XCTAssertFalse(spec.sourceID.isEmpty)
        }
    }
}
