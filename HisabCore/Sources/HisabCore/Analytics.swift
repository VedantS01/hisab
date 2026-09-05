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

    public static func categoryBreakdown(_ txns: [AnalyticsTxn], month: YearMonth,
                                         top: Int) -> [(category: String, paise: Int64)] {
        let debits = txns.filter { $0.month == month && $0.direction == .debit }
        let totals = Dictionary(grouping: debits, by: \.category)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.amountPaise } }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard totals.count > top else { return totals.map { ($0.key, $0.value) } }
        let head = totals.prefix(top).map { ($0.key, $0.value) }
        let rest = totals.dropFirst(top).reduce(Int64(0)) { $0 + $1.value }
        return head + [("Other", rest)]
    }

    public static func topMerchants(_ txns: [AnalyticsTxn], month: YearMonth,
                                    top: Int) -> [(merchant: String, paise: Int64)] {
        let debits = txns.filter { $0.month == month && $0.direction == .debit }
        return Dictionary(grouping: debits, by: \.merchant)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.amountPaise } }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(top)
            .map { ($0.key, $0.value) }
    }
}
