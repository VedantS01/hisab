import Foundation

/// The categories worth offering as one-tap answers on a notification.
public enum CategoryRanker {
    public static let windowDays = 90

    /// Highest debit *count* over the trailing window. Count, not spend: the
    /// question is "what does this user usually buy", and one large payment
    /// should not outrank a habit. Excluded: the two non-answers and self
    /// transfers. Ties break alphabetically so the buttons are deterministic.
    public static func topCategories(records: [SpendRecord], now: Date,
                                     limit: Int) -> [String] {
        let excluded: Set<String> = [Categorizer.uncategorized,
                                     Categorizer.miscellaneous,
                                     Categorizer.selfTransfer]
        let windowStart = now.addingTimeInterval(-Double(windowDays) * 86_400)
        var counts: [String: Int] = [:]
        for record in records
        where record.direction == .debit
            && record.date >= windowStart
            && record.date <= now
            && !excluded.contains(record.effectiveCategory) {
            counts[record.effectiveCategory, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}
