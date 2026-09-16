import XCTest
@testable import HisabCore

final class ChainInterpreterTests: XCTestCase {
    // Shared story: open 1,000.00 → spend 100.00 (900.00) → receive 50.00 (950.00)
    // → spend 200.00 (750.00). Every layout below encodes the same movements.

    func testDebitCreditColumnsValidate() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "R1", "100.00", "", "900.00"],
            ["02/04/2026", "SALARY",     "R2", "", "50.00", "950.00"],
            ["03/04/2026", "UPI GROCER", "R3", "200.00", "", "750.00"],
        ]
        let m = ColumnMapping(date: 0, narration: 1, reference: 2,
                              debit: 3, credit: 4, balance: 5, dateFormat: "dd/MM/yyyy")
        guard case .validated(let txns) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected validation")
        }
        XCTAssertEqual(txns.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual(txns.map(\.amountPaise), [10_000, 5_000, 20_000])
        XCTAssertEqual(txns[0].reference, "R1")
        XCTAssertEqual(txns[1].counterparty, "SALARY")
    }

    func testSignedAmountValidates() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "-100.00", "900.00"],
            ["02/04/2026", "SALARY",     "50.00",   "950.00"],
        ]
        let m = ColumnMapping(date: 0, narration: 1, amount: 2, balance: 3,
                              dateFormat: "dd/MM/yyyy")
        guard case .validated(let txns) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected validation")
        }
        XCTAssertEqual(txns.map(\.direction), [.debit, .credit])
        XCTAssertEqual(txns.map(\.amountPaise), [10_000, 5_000])
        // No reference column → synthetic balance-keyed refs.
        XCTAssertTrue(txns[0].reference!.hasPrefix("B90000D20260401A10000"))
    }

    func testDRCRQualifierValidates() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "100.00", "DR", "900.00"],
            ["02/04/2026", "SALARY",     "50.00",  "cr", "950.00"],
        ]
        let m = ColumnMapping(date: 0, narration: 1, amount: 2, drcr: 3, balance: 4,
                              dateFormat: "dd/MM/yyyy")
        guard case .validated(let txns) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected validation")
        }
        XCTAssertEqual(txns.map(\.direction), [.debit, .credit])
    }

    func testUnsignedAmountRecoversDirectionsFromChain() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "100.00", "900.00"],
            ["02/04/2026", "SALARY",     "50.00",  "950.00"],
            ["03/04/2026", "UPI GROCER", "200.00", "750.00"],
        ]
        let m = ColumnMapping(date: 0, narration: 1, amount: 2, balance: 3,
                              amountIsUnsigned: true, dateFormat: "dd/MM/yyyy")
        guard case .validated(let txns) = ChainInterpreter.interpret(rows: rows, mapping: m,
                                                                     openingBalancePaise: 100_000) else {
            return XCTFail("expected validation")
        }
        // Every direction, including row 1's, is anchored by the opening balance.
        XCTAssertEqual(txns.map(\.direction), [.debit, .credit, .debit])
    }

    func testUnsignedAmountWithoutOpeningBalanceIsAmbiguous() {
        // With no opening balance, row 1's direction can never be proven:
        // conservative outcome is a break, not a guess.
        let rows = [
            ["01/04/2026", "POS COFFEE", "100.00", "900.00"],
            ["02/04/2026", "SALARY",     "50.00",  "950.00"],
        ]
        let m = ColumnMapping(date: 0, narration: 1, amount: 2, balance: 3,
                              amountIsUnsigned: true, dateFormat: "dd/MM/yyyy")
        guard case .broken(let row, let detail) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected ambiguity break")
        }
        XCTAssertEqual(row, 0)
        XCTAssertTrue(detail.contains("ambiguous"))
    }

    func testChainBreakReportsRow() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "R1", "100.00", "", "900.00"],
            ["02/04/2026", "SALARY",     "R2", "", "50.00", "999.00"],  // tampered
        ]
        let m = ColumnMapping(date: 0, narration: 1, reference: 2,
                              debit: 3, credit: 4, balance: 5, dateFormat: "dd/MM/yyyy")
        guard case .broken(let row, _) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected chain break")
        }
        XCTAssertEqual(row, 1)
    }

    func testColumnDirectionDisagreeingWithChainIsBroken() {
        let rows = [
            ["01/04/2026", "POS COFFEE", "R1", "100.00", "", "900.00"],
            ["02/04/2026", "SALARY",     "R2", "50.00", "", "950.00"],  // debit col, but chain says credit
        ]
        let m = ColumnMapping(date: 0, narration: 1, reference: 2,
                              debit: 3, credit: 4, balance: 5, dateFormat: "dd/MM/yyyy")
        guard case .broken(let row, _) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected disagreement break")
        }
        XCTAssertEqual(row, 1)
    }

    func testUnparseableCellIsBroken() {
        let rows = [["banana", "POS", "R1", "100.00", "", "900.00"]]
        let m = ColumnMapping(date: 0, narration: 1, reference: 2,
                              debit: 3, credit: 4, balance: 5, dateFormat: "dd/MM/yyyy")
        guard case .broken(let row, let detail) = ChainInterpreter.interpret(rows: rows, mapping: m) else {
            return XCTFail("expected break")
        }
        XCTAssertEqual(row, 0)
        XCTAssertTrue(detail.contains("banana"))
    }
}
