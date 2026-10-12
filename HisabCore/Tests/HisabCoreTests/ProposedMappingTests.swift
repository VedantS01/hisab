import XCTest
@testable import HisabCore

final class ProposedMappingTests: XCTestCase {
    private struct Fixed: ColumnRoleProposer {
        let roles: ColumnRoles?
        func propose(header: [String]?, rows: [[String]]) async throws -> ColumnRoles? { roles }
    }

    private struct Failing: ColumnRoleProposer {
        struct Unavailable: Error {}
        func propose(header: [String]?, rows: [[String]]) async throws -> ColumnRoles? { throw Unavailable() }
    }

    /// An unsigned amount column, an opening-balance line and a closing line:
    /// `ColumnInference` refuses it (the closing line isn't a date, and it never
    /// reads amounts as unsigned), but with the columns named the balance chain
    /// settles every direction, the first row's included.
    private let unsignedCSV = """
        XYZ BANK LTD
        Date,Details,Ref,Amount,Balance
        Opening Balance,,,,1000.00
        01/04/2026,POS COFFEE,R1,100.00,900.00
        02/04/2026,SALARY ACME,R2,50.00,950.00
        03/04/2026,UPI GROCER,R3,200.00,750.00
        Closing Balance,,,350.00,750.00
        """
    private let roles = ColumnRoles(date: 0, narration: 1, reference: 2, amount: 3, balance: 4)

    private var table: NormalizedTable {
        NormalizedTable.from(data: Data(unsignedCSV.utf8), filename: "statement.csv", password: nil)!
    }

    func testRulesAloneRefuse() {
        XCTAssertNil(ColumnInference.infer(table: table))
    }

    func testProposedColumnsReadTheTableWhenTheChainCloses() async throws {
        let read = await ProposedMapping.read(table: table, proposer: Fixed(roles: roles))
        let result = try XCTUnwrap(read)
        XCTAssertEqual(result.transactions.map(\.amountPaise), [100_00, 50_00, 200_00])
        XCTAssertEqual(result.transactions.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual(result.transactions.map(\.reference), ["R1", "R2", "R3"])
        XCTAssertEqual(result.transactions.map(\.narration), ["POS COFFEE", "SALARY ACME", "UPI GROCER"])
        XCTAssertTrue(result.mapping.amountIsUnsigned)
    }

    func testOneLegCalledTheAmountStillReadsAsLegs() async throws {
        // What the on-device model says of HDFC's "Withdrawal Amt." /
        // "Deposit Amt.": a debit column and an amount column.
        let csv = """
            Date,Narration,Withdrawal Amt.,Deposit Amt.,Closing Balance
            01/04/25,UPI-SAHUL,14.00,,10041.58
            02/04/25,NEFT CR-MR VEDANT,,2000.00,12041.58
            03/04/25,UPI-SWIGGY,436.00,,11605.58
            """
        let table = NormalizedTable.from(data: Data(csv.utf8), filename: "statement.csv", password: nil)!
        let proposal = ColumnRoles(date: 0, narration: 1, debit: 2, amount: 3, balance: 4)
        let read = await ProposedMapping.read(table: table, proposer: Fixed(roles: proposal))
        let result = try XCTUnwrap(read)
        XCTAssertEqual(result.transactions.map(\.direction), [.debit, .credit, .debit])
        XCTAssertEqual([result.mapping.debit, result.mapping.credit], [2, 3])
    }

    func testRightmostMoneyColumnStandsInForAMissingBalanceLabel() throws {
        #if canImport(FoundationModels)
        guard #available(macOS 26, iOS 26, *) else { throw XCTSkip("FoundationModels needs macOS 26") }
        // What the model says of HDFC's columns under greedy decoding.
        let roles = OnDeviceColumnReader.roles(from: ["date", "narration", "reference", "valueDate", "debit", "credit", "amount"])
        XCTAssertEqual(roles, ColumnRoles(date: 0, narration: 1, reference: 2, debit: 4, credit: 5, balance: 6))
        #else
        throw XCTSkip("FoundationModels unavailable")
        #endif
    }

    func testWrongProposalIsARefusal() async {
        var swapped = roles
        (swapped.amount, swapped.balance) = (4, 3)
        let result = await ProposedMapping.read(table: table, proposer: Fixed(roles: swapped))
        XCTAssertNil(result)
    }

    func testColumnOutsideTheTableIsARefusal() async {
        var wrong = roles
        wrong.reference = 9
        let result = await ProposedMapping.read(table: table, proposer: Fixed(roles: wrong))
        XCTAssertNil(result)
    }

    func testUnsignedAmountsWithoutAnOpeningLineStayUnread() async {
        // Nothing anchors the first row's direction, so both readings close.
        let csv = unsignedCSV.replacingOccurrences(of: "Opening Balance,,,,1000.00\n", with: "")
        let table = NormalizedTable.from(data: Data(csv.utf8), filename: "statement.csv", password: nil)!
        let result = await ProposedMapping.read(table: table, proposer: Fixed(roles: roles))
        XCTAssertNil(result)
    }

    func testResolverFallsBackToTheProposerOnlyOnRefusal() async {
        let resolver = ImportResolver(registry: ParserRegistry(parsers: []), specs: [])
        let data = Data(unsignedCSV.utf8)
        guard case .unsupported = resolver.resolve(data: data, filename: "statement.csv", password: nil) else {
            return XCTFail("rules alone should refuse")
        }
        guard case .parsed(let doc) = await resolver.resolve(data: data, filename: "statement.csv", password: nil,
                                                             proposer: Fixed(roles: roles)) else {
            return XCTFail("proposed columns should read it")
        }
        XCTAssertEqual(doc.transactions.count, 3)
        XCTAssertTrue(doc.source.rawValue.hasPrefix("bank:"))

        guard case .unsupported = await resolver.resolve(data: data, filename: "statement.csv", password: nil,
                                                         proposer: Failing()) else {
            return XCTFail("a proposer that fails leaves the refusal as it was")
        }
    }

    /// Apple's on-device model on this machine. Opt-in (HISAB_LIVE_MODEL=1): it
    /// needs Apple Intelligence, takes seconds, and its answers can vary.
    func testOnDeviceModelReadsTheTable() async throws {
        guard ProcessInfo.processInfo.environment["HISAB_LIVE_MODEL"] != nil else {
            throw XCTSkip("HISAB_LIVE_MODEL not set")
        }
        #if canImport(FoundationModels)
        guard #available(macOS 26, iOS 26, *), OnDeviceColumnReader.isAvailable else {
            throw XCTSkip("on-device model unavailable")
        }
        let read = await ProposedMapping.read(table: table, proposer: OnDeviceColumnReader())
        let result = try XCTUnwrap(read)
        XCTAssertEqual(result.transactions.map(\.direction), [.debit, .credit, .debit])
        #else
        throw XCTSkip("FoundationModels unavailable")
        #endif
    }

}
