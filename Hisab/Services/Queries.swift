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

    /// UUIDs of bank rows confirmed as the bank-side copy of an app payment.
    static func matchedBankUUIDs(_ ctx: ModelContext) -> Set<UUID> {
        Set(((try? ctx.fetch(FetchDescriptor<StoredMatch>())) ?? []).map(\.bankUUID))
    }

    /// UUIDs of cross-bank self-transfer pairs (HDFC↔IDFC internal movements).
    static func selfTransferUUIDs(_ ctx: ModelContext) -> Set<UUID> {
        let bank = allTransactions(ctx).filter { $0.source.kind == .bank }
        return SelfTransfers.detect(bank: bank.map {
            (ReconTxn(id: $0.uuid, date: $0.date, amountPaise: $0.amountPaise,
                      direction: $0.direction, reference: $0.reference), $0.source)
        })
    }

    /// The recorded history: every payment-app transaction, plus bank rows that have no
    /// app counterpart. Matched bank rows are reconciliation evidence, not records;
    /// self transfers are shown only under their own category.
    static func visibleTransactions(_ ctx: ModelContext) -> [StoredTransaction] {
        let matched = matchedBankUUIDs(ctx)
        return allTransactions(ctx).filter { !matched.contains($0.uuid) }
    }

    /// Display/analytics category. Bank-only rows fall back to Miscellaneous rather
    /// than Uncategorized; self transfers are labeled as such.
    static func effectiveCategory(of txn: StoredTransaction, rules: [CategoryRule],
                                  selfTransfers: Set<UUID>) -> String {
        if selfTransfers.contains(txn.uuid) { return Categorizer.selfTransfer }
        if let override = txn.categoryOverride { return override }
        let auto = Categorizer.category(for: "\(txn.counterparty) \(txn.narration)", rules: rules)
        if auto == Categorizer.uncategorized && txn.source.kind == .bank {
            return Categorizer.miscellaneous
        }
        return auto
    }

    /// Counted rows only: visible history minus self transfers.
    static func analyticsTxns(_ ctx: ModelContext) -> [AnalyticsTxn] {
        let rules = categoryRules(ctx)
        let selfTransfers = selfTransferUUIDs(ctx)
        return visibleTransactions(ctx)
            .filter { !selfTransfers.contains($0.uuid) }
            .map { txn in
                AnalyticsTxn(month: txn.month,
                             amountPaise: txn.amountPaise,
                             direction: txn.direction,
                             category: effectiveCategory(of: txn, rules: rules, selfTransfers: []),
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
    /// Self-transfer rows are internal movements — kept out of the bank side.
    static func recomputeMatches(_ ctx: ModelContext, month: YearMonth) {
        for row in matches(ctx, month: month) { ctx.delete(row) }
        let (app, rawBank) = reconTxns(ctx, month: month)
        let selfTransfers = selfTransferUUIDs(ctx)
        let bank = rawBank.filter { !selfTransfers.contains($0.id) }
        guard !app.isEmpty, !bank.isEmpty else { return }
        let result = Reconciler.reconcile(app: app, bank: bank)
        for pair in result.matches {
            ctx.insert(StoredMatch(appUUID: pair.appID, bankUUID: pair.bankID, tier: pair.tier, month: month))
        }
    }
}
