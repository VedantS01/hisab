import Foundation
import SwiftData
import HisabCore

/// Fetch helpers bridging SwiftData rows to HisabCore value types.
@MainActor
enum Queries {
    static func documents(_ ctx: ModelContext) -> [DocumentSummary] {
        let docs = (try? ctx.fetch(FetchDescriptor<StoredDocument>())) ?? []
        return docs.map { DocumentSummary(id: $0.uuid, source: $0.source, period: $0.period) }
    }

    static func allTransactions(_ ctx: ModelContext) -> [StoredTransaction] {
        (try? ctx.fetch(FetchDescriptor<StoredTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// Seeds the rule table from Categorizer defaults on first launch.
    static func categoryRules(_ ctx: ModelContext) -> [CategoryRule] {
        var stored = (try? ctx.fetch(FetchDescriptor<StoredCategoryRule>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        if stored.isEmpty {
            for (index, rule) in Categorizer.seedRules.enumerated() {
                ctx.insert(StoredCategoryRule(pattern: rule.pattern, category: rule.category, sortOrder: index))
            }
            try? ctx.save()
            stored = (try? ctx.fetch(FetchDescriptor<StoredCategoryRule>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        }
        return stored.map(\.asRule)
    }

    static func category(of txn: StoredTransaction, rules: [CategoryRule]) -> String {
        txn.categoryOverride ?? Categorizer.category(for: "\(txn.counterparty) \(txn.narration)", rules: rules)
    }

    static func analyticsTxns(_ ctx: ModelContext) -> [AnalyticsTxn] {
        let rules = categoryRules(ctx)
        return allTransactions(ctx).map { txn in
            AnalyticsTxn(month: txn.month,
                         amountPaise: txn.amountPaise,
                         direction: txn.direction,
                         category: category(of: txn, rules: rules),
                         merchant: txn.counterparty,
                         sourceKind: txn.source.kind)
        }
    }

    static func transactions(_ ctx: ModelContext, month: YearMonth) -> [StoredTransaction] {
        allTransactions(ctx).filter { $0.month == month }
    }

    static func reconTxns(_ ctx: ModelContext, month: YearMonth) -> (app: [ReconTxn], bank: [ReconTxn]) {
        let monthTxns = transactions(ctx, month: month)
        func projected(_ kind: SourceKind) -> [ReconTxn] {
            monthTxns.filter { $0.source.kind == kind }
                .map { ReconTxn(id: $0.uuid, date: $0.date, amountPaise: $0.amountPaise,
                                direction: $0.direction, reference: $0.reference) }
        }
        return (projected(.paymentApp), projected(.bank))
    }

    static func matches(_ ctx: ModelContext, month: YearMonth) -> [StoredMatch] {
        let key = month.description
        let descriptor = FetchDescriptor<StoredMatch>(predicate: #Predicate { $0.monthKey == key })
        return (try? ctx.fetch(descriptor)) ?? []
    }

    static func pinned(_ ctx: ModelContext) -> Set<YearMonth> {
        let rows = (try? ctx.fetch(FetchDescriptor<PinnedMonth>())) ?? []
        return Set(rows.map(\.yearMonth))
    }

    static func coverageGrid(_ ctx: ModelContext) -> CoverageGrid {
        CoverageGrid.derive(documents: documents(ctx), pinnedMonths: pinned(ctx))
    }

    /// Replaces the stored reconciliation for one month with a fresh run.
    static func recomputeMatches(_ ctx: ModelContext, month: YearMonth) {
        for row in matches(ctx, month: month) { ctx.delete(row) }
        let (app, bank) = reconTxns(ctx, month: month)
        guard !app.isEmpty, !bank.isEmpty else { return }
        let result = Reconciler.reconcile(app: app, bank: bank)
        for pair in result.matches {
            ctx.insert(StoredMatch(appUUID: pair.appID, bankUUID: pair.bankID, tier: pair.tier, month: month))
        }
    }
}
