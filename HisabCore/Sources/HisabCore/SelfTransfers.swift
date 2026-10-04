import Foundation

/// Detects bank→bank self transfers between the user's own accounts: a debit in one
/// bank source paired with an equal credit in a *different* bank source within the
/// date window. Both sides are internal movements — neither expense nor income.
public enum SelfTransfers {
    public static func detect(bank: [(txn: ReconTxn, source: Source)],
                              dateWindowDays: Int = 2) -> Set<UUID> {
        let window = TimeInterval(dateWindowDays) * 86_400
        let debits = bank.filter { $0.txn.direction == .debit }
        var credits = bank.filter { $0.txn.direction == .credit }
        var flagged = Set<UUID>()

        for debit in debits.sorted(by: { $0.txn.date < $1.txn.date }) {
            let candidates = credits.enumerated()
                .filter { _, credit in
                    credit.source != debit.source
                        && credit.txn.amountPaise == debit.txn.amountPaise
                        && abs(credit.txn.date.timeIntervalSince(debit.txn.date)) <= window
                }
                .sorted { lhs, rhs in
                    abs(lhs.element.txn.date.timeIntervalSince(debit.txn.date))
                        < abs(rhs.element.txn.date.timeIntervalSince(debit.txn.date))
                }
            if let (index, credit) = candidates.first {
                flagged.insert(debit.txn.id)
                flagged.insert(credit.txn.id)
                credits.remove(at: index)
            }
        }
        return flagged
    }

    /// Captured-alert rows (`Source.alert`) that are legs of a transfer between
    /// the user's own accounts. Alert rows are payment-app side, so `detect`
    /// never sees them; without this, one transfer alerted on both accounts
    /// would count as spending and as income.
    ///
    /// A row is a self transfer when another alert row has the same reference
    /// and the opposite direction (one IMPS ref appears in the sending bank's
    /// debit alert and the receiving bank's credit alert), or when its
    /// reference is on a bank row `detect` already flagged.
    public static func alerts(_ rows: [(id: UUID, reference: String, direction: Direction)],
                              bankSelfTransferRefs: Set<String>) -> Set<UUID> {
        var directions: [String: Set<Direction>] = [:]
        for row in rows { directions[row.reference, default: []].insert(row.direction) }
        return Set(rows.filter { row in
            directions[row.reference]?.count == 2 || bankSelfTransferRefs.contains(row.reference)
        }.map(\.id))
    }
}
