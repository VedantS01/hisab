import Foundation

/// One "counted" row for analytics. The app layer feeds every payment-app transaction
/// plus unmatched bank rows (category "Miscellaneous" when no rule hits); matched bank
/// rows (reconciliation evidence) and cross-bank self transfers are excluded upstream,
/// so nothing here is double-counted.
public struct AnalyticsTxn: Sendable {
    public let month: YearMonth
    public let amountPaise: Int64
    public let direction: Direction
    public let category: String
    public let merchant: String
    public let sourceKind: SourceKind

    public init(month: YearMonth, amountPaise: Int64, direction: Direction,
                category: String, merchant: String, sourceKind: SourceKind) {
        self.month = month
        self.amountPaise = amountPaise
        self.direction = direction
        self.category = category
        self.merchant = merchant
        self.sourceKind = sourceKind
    }
}

public struct MonthStats: Sendable, Equatable {
    public let month: YearMonth
    public let spendPaise: Int64
    public let incomePaise: Int64

    public var netPaise: Int64 { incomePaise - spendPaise }
}

public enum Analytics {
    public static func monthStats(_ txns: [AnalyticsTxn], month: YearMonth) -> MonthStats {
        let monthTxns = txns.filter { $0.month == month }
        let spend = monthTxns.filter { $0.direction == .debit }.reduce(Int64(0)) { $0 + $1.amountPaise }
        let income = monthTxns.filter { $0.direction == .credit }.reduce(Int64(0)) { $0 + $1.amountPaise }
        return MonthStats(month: month, spendPaise: spend, incomePaise: income)
    }

    public static func trend(_ txns: [AnalyticsTxn], endingAt end: YearMonth, count: Int) -> [MonthStats] {
        YearMonth.months(from: end.advanced(by: -(count - 1)), through: end)
            .map { monthStats(txns, month: $0) }
    }

    /// Sum of debit amounts per grouping key, largest first (ties alphabetical).
    /// Kept as explicit steps — older Swift compilers time out on the fused chain.
    private static func debitTotals(_ txns: [AnalyticsTxn], month: YearMonth,
                                    by key: (AnalyticsTxn) -> String) -> [(String, Int64)] {
        let debits = txns.filter { $0.month == month && $0.direction == .debit }
        var totals: [String: Int64] = [:]
        for txn in debits {
            totals[key(txn), default: 0] += txn.amountPaise
        }
        return totals.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
    }

    public static func categoryBreakdown(_ txns: [AnalyticsTxn], month: YearMonth,
                                         top: Int) -> [(category: String, paise: Int64)] {
        let totals = debitTotals(txns, month: month, by: \.category)
        var result = totals.map { (category: $0.0, paise: $0.1) }
        guard result.count > top else { return result }
        var rest: Int64 = 0
        for entry in result.dropFirst(top) {
            rest += entry.paise
        }
        result = Array(result.prefix(top))
        result.append((category: "Other", paise: rest))
        return result
    }

    public static func topMerchants(_ txns: [AnalyticsTxn], month: YearMonth,
                                    top: Int) -> [(merchant: String, paise: Int64)] {
        debitTotals(txns, month: month, by: \.merchant).prefix(top)
            .map { (merchant: $0.0, paise: $0.1) }
    }
}
