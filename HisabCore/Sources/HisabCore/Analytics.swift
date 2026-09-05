import Foundation

/// Month-resolved, categorized projection of a stored transaction.
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

public enum Basis: String, Sendable {
    case bank, paymentApps, none
}

public struct MonthStats: Sendable, Equatable {
    public let month: YearMonth
    public let spendPaise: Int64
    public let incomePaise: Int64
    public let basis: Basis

    public var netPaise: Int64 { incomePaise - spendPaise }
}

public enum Analytics {
    /// Basis rule: months with any bank-side data trust ONLY the bank (payment-app rows
    /// are a subset of it, deduped or not); months without fall back to payment apps.
    static func basisTxns(_ txns: [AnalyticsTxn], month: YearMonth) -> (txns: [AnalyticsTxn], basis: Basis) {
        let monthTxns = txns.filter { $0.month == month }
        guard !monthTxns.isEmpty else { return ([], .none) }
        let bankTxns = monthTxns.filter { $0.sourceKind == .bank }
        if bankTxns.isEmpty { return (monthTxns, .paymentApps) }
        return (bankTxns, .bank)
    }

    public static func monthStats(_ txns: [AnalyticsTxn], month: YearMonth) -> MonthStats {
        let (basisTxns, basis) = basisTxns(txns, month: month)
        let spend = basisTxns.filter { $0.direction == .debit }.reduce(Int64(0)) { $0 + $1.amountPaise }
        let income = basisTxns.filter { $0.direction == .credit }.reduce(Int64(0)) { $0 + $1.amountPaise }
        return MonthStats(month: month, spendPaise: spend, incomePaise: income, basis: basis)
    }

    public static func trend(_ txns: [AnalyticsTxn], endingAt end: YearMonth, count: Int) -> [MonthStats] {
        YearMonth.months(from: end.advanced(by: -(count - 1)), through: end)
            .map { monthStats(txns, month: $0) }
    }

    public static func categoryBreakdown(_ txns: [AnalyticsTxn], month: YearMonth,
                                         top: Int) -> [(category: String, paise: Int64)] {
        let debits = basisTxns(txns, month: month).txns.filter { $0.direction == .debit }
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
        let debits = basisTxns(txns, month: month).txns.filter { $0.direction == .debit }
        return Dictionary(grouping: debits, by: \.merchant)
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.amountPaise } }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(top)
            .map { ($0.key, $0.value) }
    }
}
