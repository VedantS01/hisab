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
}
