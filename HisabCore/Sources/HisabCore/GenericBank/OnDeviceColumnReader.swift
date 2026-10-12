#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple's on-device language model reading a statement table's header and
/// first rows. Nothing leaves the device, and nothing it says is trusted until
/// the balance chain closes under it (see `ProposedMapping`).
@available(iOS 26, macOS 26, *)
public struct OnDeviceColumnReader: ColumnRoleProposer {
    public init() {}

    /// False without Apple Intelligence: an unsupported device, the feature
    /// switched off, or the model still downloading.
    public static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    public func propose(header: [String]?, rows: [[String]]) async throws -> ColumnRoles? {
        guard Self.isAvailable else { return nil }
        let width = ([header ?? []] + rows).map(\.count).max() ?? 0
        let session = LanguageModelSession(instructions: Self.instructions)
        // Greedy: the most likely labels, the same ones every time.
        let content = try await session.respond(to: Self.prompt(header: header, rows: rows),
                                                schema: Self.schema(header: header, rows: rows, width: width),
                                                options: GenerationOptions(sampling: .greedy)).content
        return Self.roles(from: try (0..<width).map { try content.value(String.self, forProperty: "column\($0)") })
    }

    static let kinds = ["date", "valueDate", "narration", "reference", "debit", "credit", "amount", "drcrMarker",
                        "balance", "other"]

    static let instructions = """
        You read the transaction table of a bank account statement and label every \
        column with what it holds: date (the transaction date), valueDate (a second \
        date column), narration (description or particulars), reference (cheque or \
        reference number), debit (withdrawals), credit (deposits), amount (one column \
        holding both debits and credits), drcrMarker (Dr or Cr), balance (the running \
        balance), or other. A statement has one balance column, usually the last.
        """

    /// "Header: 0: Date | 1: Narration | …" then one such line per row, cells
    /// cut to 40 characters.
    static func prompt(header: [String]?, rows: [[String]]) -> String {
        func line(_ cells: [String]) -> String {
            cells.enumerated().map { "\($0): \($1.prefix(40))" }.joined(separator: " | ")
        }
        return (header.map { "Header: \(line($0))\n" } ?? "") + "Rows:\n" + rows.map(line).joined(separator: "\n")
    }

    /// One required label per column, described by its header and first
    /// values. Asked for a list, the model echoes the label vocabulary; asked
    /// for optional slots, it fills every one with the same column. A field
    /// per column is the shape it answers reliably.
    static func schema(header: [String]?, rows: [[String]], width: Int) throws -> GenerationSchema {
        let kind = DynamicGenerationSchema(name: "Kind", anyOf: kinds)
        let columns = (0..<width).map { column in
            let title = header.flatMap { column < $0.count ? $0[column] : nil } ?? ""
            let values = rows.prefix(3).compactMap { column < $0.count && !$0[column].isEmpty ? "'\($0[column].prefix(30))'" : nil }
            return DynamicGenerationSchema.Property(
                name: "column\(column)",
                description: "Column \(column)" + (title.isEmpty ? "" : ", headed '\(title)'")
                    + (values.isEmpty ? ", mostly empty" : ", values like \(values.joined(separator: ", "))"),
                schema: DynamicGenerationSchema(referenceTo: "Kind"))
        }
        return try GenerationSchema(root: DynamicGenerationSchema(name: "Columns", properties: columns),
                                    dependencies: [kind])
    }

    /// With no column labelled balance, the rightmost money column: the model
    /// sometimes calls HDFC's "Closing Balance" an amount, and a running
    /// balance is the last money column on every statement it has seen.
    static func roles(from kinds: [String]) -> ColumnRoles? {
        func first(_ kind: String) -> Int? { kinds.firstIndex(of: kind) }
        guard let date = first("date") ?? first("valueDate"), let narration = first("narration"),
              let balance = first("balance") ?? kinds.lastIndex(where: { ["debit", "credit", "amount"].contains($0) })
        else { return nil }
        func money(_ kind: String) -> Int? { kinds.indices.first { kinds[$0] == kind && $0 != balance } }
        return ColumnRoles(date: date, narration: narration, reference: first("reference"),
                           debit: money("debit"), credit: money("credit"), amount: money("amount"),
                           drcr: first("drcrMarker"), balance: balance)
    }
}
#endif
