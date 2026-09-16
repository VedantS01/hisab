import Foundation

/// One transaction as the suggestion engine sees it (the app projects stored
/// rows into this; `effectiveCategory` already accounts for overrides/rules).
public struct SpendRecord: Sendable, Equatable {
    public var merchant: String
    public var amountPaise: Int64
    public var date: Date
    public var direction: Direction
    public var effectiveCategory: String

    public init(merchant: String, amountPaise: Int64, date: Date,
                direction: Direction, effectiveCategory: String) {
        self.merchant = merchant
        self.amountPaise = amountPaise
        self.date = date
        self.direction = direction
        self.effectiveCategory = effectiveCategory
    }
}

public struct RuleSuggestion: Equatable, Sendable {
    public var merchantPattern: String   // normalized cluster key → CategoryRule.pattern
    public var displayMerchant: String   // most common raw merchant in the cluster
    public var totalPaise: Int64
    public var count: Int
}

/// Finds recurring, substantial, uncategorized spending worth one polite
/// prompt. Gates (per the design spec): trailing 90 days; cluster total ≥
/// max(₹500, 2% of the window's total debits); ≥3 transactions across ≥2
/// months; muted merchants never return. Ordered by spend impact.
public enum SuggestionEngine {
    public static func normalize(_ merchant: String) -> String {
        var cleaned = ""
        for ch in merchant.lowercased() {
            if ch.isLetter { cleaned.append(ch) } else { cleaned.append(" ") }
        }
        let tokens = cleaned.split(separator: " ").prefix(3)
        return tokens.joined(separator: " ")
    }

    public static func queue(records: [SpendRecord], now: Date,
                             muted: Set<String>) -> [RuleSuggestion] {
        let windowStart = now.addingTimeInterval(-90 * 86_400)

        var windowDebitTotal: Int64 = 0
        var clusters: [String: [SpendRecord]] = [:]
        for record in records {
            guard record.direction == .debit,
                  record.date >= windowStart, record.date <= now else { continue }
            windowDebitTotal += record.amountPaise
            let uncategorized = record.effectiveCategory == Categorizer.uncategorized
                || record.effectiveCategory == Categorizer.miscellaneous
            guard uncategorized else { continue }
            let key = normalize(record.merchant)
            guard !key.isEmpty, !muted.contains(key) else { continue }
            clusters[key, default: []].append(record)
        }

        let floor: Int64 = 50_000  // ₹500
        let threshold = max(floor, windowDebitTotal * 2 / 100)

        var suggestions: [RuleSuggestion] = []
        for (key, members) in clusters {
            guard members.count >= 3 else { continue }
            let months = Set(members.map { YearMonth(date: $0.date) })
            guard months.count >= 2 else { continue }
            var total: Int64 = 0
            var rawCounts: [String: Int] = [:]
            for member in members {
                total += member.amountPaise
                rawCounts[member.merchant, default: 0] += 1
            }
            guard total >= threshold else { continue }
            let display = rawCounts.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
            }?.key ?? key
            suggestions.append(RuleSuggestion(merchantPattern: key,
                                              displayMerchant: display,
                                              totalPaise: total,
                                              count: members.count))
        }
        return suggestions.sorted { lhs, rhs in
            lhs.totalPaise == rhs.totalPaise
                ? lhs.merchantPattern < rhs.merchantPattern
                : lhs.totalPaise > rhs.totalPaise
        }
    }
}
