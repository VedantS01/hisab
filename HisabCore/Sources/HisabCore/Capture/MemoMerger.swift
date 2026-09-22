import Foundation

/// A statement row a memo might turn out to be.
public struct MemoMergeCandidate: Sendable, Equatable {
    public var id: UUID
    public var date: Date
    public var amountPaise: Int64
    public var direction: Direction
    public var narration: String

    public init(id: UUID, date: Date, amountPaise: Int64, direction: Direction,
                narration: String) {
        self.id = id
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.narration = narration
    }
}

/// Retires memos against imported statement rows.
///
/// The triple gate — exact amount, same direction, within ±3 days, and a
/// payee or VPA that actually appears in the narration — is intentionally
/// strict. An unmerged memo simply expires; a wrongly merged one silently
/// moves the user's note onto somebody else's payment.
public enum MemoMerger {
    public static let windowDays = 3

    /// `captureHash -> transaction id`. Each candidate is claimed at most once.
    public static func merge(memos: [PendingMemo],
                             candidates: [MemoMergeCandidate]) -> [String: UUID] {
        // Deterministic order so two runs (and two languages) agree.
        let ordered = memos.sorted {
            $0.date == $1.date ? $0.captureHash < $1.captureHash : $0.date < $1.date
        }
        var claimed = Set<UUID>()
        var result: [String: UUID] = [:]

        for memo in ordered {
            let matching = candidates
                .filter { !claimed.contains($0.id) && matches(memo: memo, candidate: $0) }
                .sorted { lhs, rhs in
                    let l = abs(lhs.date.timeIntervalSince(memo.date))
                    let r = abs(rhs.date.timeIntervalSince(memo.date))
                    return l == r ? lhs.id.uuidString < rhs.id.uuidString : l < r
                }
            guard let best = matching.first else { continue }
            claimed.insert(best.id)
            result[memo.captureHash] = best.id
        }
        return result
    }

    private static func matches(memo: PendingMemo, candidate: MemoMergeCandidate) -> Bool {
        guard memo.amountPaise == candidate.amountPaise,
              memo.direction == candidate.direction else { return false }
        let days = YearMonth.istCalendar.dateComponents([.day],
                                                        from: min(memo.date, candidate.date),
                                                        to: max(memo.date, candidate.date)).day ?? .max
        guard days <= windowDays else { return false }

        let narration = candidate.narration.lowercased()
        if let vpa = memo.vpa, narration.contains(vpa) { return true }
        let key = memo.payeeNormalized
        return !key.isEmpty && narration.contains(key.split(separator: " ")[0])
    }
}
