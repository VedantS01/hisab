import Foundation

/// Projection of a stored transaction for matching purposes.
public struct ReconTxn: Sendable {
    public let id: UUID
    public let date: Date
    public let amountPaise: Int64
    public let direction: Direction
    public let reference: String?

    public init(id: UUID, date: Date, amountPaise: Int64, direction: Direction, reference: String?) {
        self.id = id
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.reference = reference
    }
}

public enum MatchTier: String, Codable, Sendable {
    case reference, amountDate
}

public struct MatchPair: Sendable, Equatable {
    public let appID: UUID
    public let bankID: UUID
    public let tier: MatchTier

    public init(appID: UUID, bankID: UUID, tier: MatchTier) {
        self.appID = appID
        self.bankID = bankID
        self.tier = tier
    }
}

public struct ReconciliationResult: Sendable {
    public let matches: [MatchPair]
    public let appUnmatched: [UUID]
    public let bankOnly: [UUID]
}

public enum Reconciler {
    /// Tier 1: exact reference match. Tier 2: same (amount, direction) within ±window days,
    /// closest date first; each bank transaction consumed at most once.
    public static func reconcile(app: [ReconTxn], bank: [ReconTxn], dateWindowDays: Int = 2) -> ReconciliationResult {
        var matches: [MatchPair] = []
        var consumedBank = Set<UUID>()
        var unmatchedApp: [ReconTxn] = []

        // Tier 1 — reference
        var bankByRef: [String: ReconTxn] = [:]
        for txn in bank {
            if let ref = txn.reference, !ref.isEmpty, bankByRef[ref] == nil {
                bankByRef[ref] = txn
            }
        }
        for txn in app {
            if let ref = txn.reference, !ref.isEmpty, let hit = bankByRef[ref], !consumedBank.contains(hit.id) {
                matches.append(MatchPair(appID: txn.id, bankID: hit.id, tier: .reference))
                consumedBank.insert(hit.id)
            } else {
                unmatchedApp.append(txn)
            }
        }

        // Tier 2 — amount + date window
        let window = TimeInterval(dateWindowDays) * 86_400
        for txn in unmatchedApp.sorted(by: { $0.date < $1.date }) {
            let candidates = bank
                .filter { !consumedBank.contains($0.id)
                    && $0.amountPaise == txn.amountPaise
                    && $0.direction == txn.direction
                    && abs($0.date.timeIntervalSince(txn.date)) <= window }
                .sorted { lhs, rhs in
                    let dl = abs(lhs.date.timeIntervalSince(txn.date))
                    let dr = abs(rhs.date.timeIntervalSince(txn.date))
                    return dl == dr ? lhs.date < rhs.date : dl < dr
                }
            if let hit = candidates.first {
                matches.append(MatchPair(appID: txn.id, bankID: hit.id, tier: .amountDate))
                consumedBank.insert(hit.id)
            }
        }

        let matchedApp = Set(matches.map(\.appID))
        return ReconciliationResult(
            matches: matches,
            appUnmatched: app.filter { !matchedApp.contains($0.id) }.map(\.id),
            bankOnly: bank.filter { !consumedBank.contains($0.id) }.map(\.id)
        )
    }
}
