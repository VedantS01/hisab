import Foundation

/// Which column of a statement table holds what, as a reader proposes it.
/// Indices into the table's rows; nil where the statement has no such column.
public struct ColumnRoles: Sendable, Equatable {
    public var date: Int
    public var narration: Int
    public var reference: Int?
    public var debit: Int?
    public var credit: Int?
    public var amount: Int?
    public var drcr: Int?
    public var balance: Int

    public init(date: Int, narration: Int, reference: Int? = nil, debit: Int? = nil, credit: Int? = nil,
                amount: Int? = nil, drcr: Int? = nil, balance: Int) {
        self.date = date
        self.narration = narration
        self.reference = reference
        self.debit = debit
        self.credit = credit
        self.amount = amount
        self.drcr = drcr
        self.balance = balance
    }
}

/// Reads a statement table's columns from its header and first rows — the
/// on-device language model in the app, a fixed answer in tests.
public protocol ColumnRoleProposer: Sendable {
    func propose(header: [String]?, rows: [[String]]) async throws -> ColumnRoles?
}

/// A proposer's reading, held to the same standard as every other: the date
/// format comes from the cells, not the proposer, and the reading is accepted
/// only when every transaction's balance closes to the paisa under it. A wrong
/// proposal is a refusal, never an import.
///
/// Knowing the columns is what lets this go where `ColumnInference` can't:
/// rows whose date cell isn't a date at all (an opening-balance line, a total)
/// are set aside instead of sinking the table, and an opening-balance line's
/// balance anchors the first transaction — which is what lets an unsigned
/// amount column, whose direction only the balance reveals, be read at all.
public enum ProposedMapping {
    /// Rows shown to the proposer: enough to see each column's shape, few
    /// enough for the on-device model's context.
    static let sampleRows = 8

    /// The first rows, and then the first row that fills each column they
    /// leave empty — a page of withdrawals says nothing about the deposits.
    static func sample(_ body: [[String]]) -> [[String]] {
        var rows = Array(body.prefix(sampleRows / 2))
        let width = body.map(\.count).max() ?? 0
        for column in 0..<width where rows.count < sampleRows
            && !rows.contains(where: { column < $0.count && !$0[column].isEmpty }) {
            if let row = body.first(where: { column < $0.count && !$0[column].isEmpty }) { rows.append(row) }
        }
        for row in body where rows.count < sampleRows && !rows.contains(row) { rows.append(row) }
        return rows
    }

    public static func read(table: NormalizedTable, proposer: some ColumnRoleProposer) async -> ColumnInference.Result? {
        let (header, body) = ColumnInference.body(of: table)
        guard body.count >= 2,
              let roles = try? await proposer.propose(header: header, rows: sample(body)) else {
            return nil
        }
        let width = body.map(\.count).max() ?? 0
        let named = [roles.date, roles.narration, roles.balance]
            + [roles.reference, roles.debit, roles.credit, roles.amount, roles.drcr].compactMap { $0 }
        guard named.allSatisfy((0..<width).contains) else { return nil }

        func cell(_ row: [String], _ column: Int) -> String { column < row.count ? row[column] : "" }
        // A row is a transaction when its date cell reads as a date; one that
        // looks like a date but won't parse sinks the reading in the chain.
        let dated = body.filter { DateShapes.looksLikeDate(cell($0, roles.date)) }
        guard dated.count >= 2, let format = ColumnInference.dateFormat(parsingAll: dated.map { cell($0, roles.date) }),
              let first = table.rows.firstIndex(of: dated[0]) else { return nil }
        // The nearest number in the balance column above the first transaction:
        // an "Opening Balance" line, however few cells it has.
        let opening = table.rows[..<first].reversed()
            .lazy.compactMap { Money.signedPaise(fromDecimalString: cell($0, roles.balance)) }.first

        let base = ColumnMapping(date: roles.date, narration: roles.narration, reference: roles.reference,
                                 balance: roles.balance, dateFormat: format)
        // The proposer's own reading first. Then the columns it called debit,
        // credit or amount are taken as money columns in any arrangement — a
        // model reading "Deposit Amt." calls it the amount — since only the
        // right one closes the chain: a swapped pair contradicts the balance.
        var money: [Int] = []
        for column in [roles.debit, roles.credit, roles.amount].compactMap({ $0 })
            where column != roles.balance && !money.contains(column) {
            money.append(column)
        }
        var legs: [(debit: Int, credit: Int)] = []
        if let debit = roles.debit, let credit = roles.credit, money.contains(debit), money.contains(credit),
           debit != credit {
            legs.append((debit, credit))
        }
        for debit in money {
            for credit in money where credit != debit && !legs.contains(where: { $0 == (debit, credit) }) {
                legs.append((debit, credit))
            }
        }
        var candidates: [ColumnMapping] = legs.map { leg in
            var mapping = base
            mapping.debit = leg.debit
            mapping.credit = leg.credit
            return mapping
        }
        let amounts = roles.amount.flatMap { money.contains($0) ? [$0] + money.filter { $0 != roles.amount } : nil } ?? money
        for amount in amounts {
            var mapping = base
            mapping.amount = amount
            if let drcr = roles.drcr, drcr != amount {
                var marked = mapping
                marked.drcr = drcr
                candidates.append(marked)
            }
            // Signed if the column carries signs; else the chain decides.
            candidates.append(mapping)
            mapping.amountIsUnsigned = true
            candidates.append(mapping)
        }
        // With the opening line's balance first, so the first row is checked
        // too; without it — the first row trusted, as `ColumnInference` does —
        // when that line turns out not to be an opening balance.
        // Every arrangement that closes must read the same transactions;
        // two different readings are a refusal, as in `ColumnInference`.
        let starts: [Int64?] = opening == nil ? [nil] : [opening, nil]
        var reading: ColumnInference.Result?
        for mapping in candidates {
            for start in starts {
                guard case .validated(let transactions) = ChainInterpreter.interpret(rows: dated, mapping: mapping,
                                                                                     openingBalancePaise: start)
                else { continue }
                if let reading, reading.transactions != transactions { return nil }
                reading = reading ?? ColumnInference.Result(mapping: mapping, transactions: transactions)
            }
        }
        return reading
    }
}
