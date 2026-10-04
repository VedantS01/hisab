import Foundation
import SwiftData
import HisabCore

/// Fetch helpers bridging SwiftData rows to HisabCore value types.
@MainActor
enum Queries {
    static func documents(_ ctx: ModelContext) -> [DocumentSummary] {
        let docs = (try? ctx.fetch(FetchDescriptor<StoredDocument>())) ?? []
        return statements(docs).map { DocumentSummary(id: $0.uuid, source: $0.source, period: $0.period) }
    }

    /// Documents that say which months are covered: every one but the
    /// captured-alerts document, whose period only spans the alerts that
    /// happened to arrive. Reading it as a statement would mark a month
    /// covered, or complete, on the strength of a few SMSes.
    static func statements(_ documents: [StoredDocument]) -> [StoredDocument] {
        documents.filter { $0.source != .alert }
    }

    static func allTransactions(_ ctx: ModelContext) -> [StoredTransaction] {
        (try? ctx.fetch(FetchDescriptor<StoredTransaction>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
    }

    /// Additively seeds the rule table from the bundled india-default ruleset:
    /// any ruleset pattern the user doesn't already have (by case-insensitive
    /// pattern) is inserted; existing rules — including ones the user edited —
    /// are never touched. Idempotent, and ruleset version bumps just add rules.
    static func categoryRules(_ ctx: ModelContext) -> [CategoryRule] {
        var stored = (try? ctx.fetch(FetchDescriptor<StoredCategoryRule>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let existing = Set(stored.map { $0.pattern.lowercased() })
        let missing = Categorizer.defaultRuleset().rules.filter {
            !existing.contains($0.pattern.lowercased())
        }
        if !missing.isEmpty {
            var order = (stored.map(\.sortOrder).max() ?? -1) + 1
            for rule in missing {
                ctx.insert(StoredCategoryRule(pattern: rule.pattern, category: rule.category, sortOrder: order))
                order += 1
            }
            try? ctx.save()
            stored = (try? ctx.fetch(FetchDescriptor<StoredCategoryRule>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        }
        return stored.map(\.asRule)
    }

    static func category(of txn: StoredTransaction, rules: [CategoryRule]) -> String {
        txn.categoryOverride ?? Categorizer.category(for: "\(txn.counterparty) \(txn.narration)", rules: rules)
    }

    // MARK: pure projections over already-fetched rows
    // Views feed these from @Query so SwiftData changes invalidate them automatically —
    // a view that computes from a ModelContext fetch alone never refreshes (the bug that
    // left the Transactions tab stale on-device).

    static func rules(from rows: [StoredCategoryRule]) -> [CategoryRule] {
        rows.map(\.asRule)
    }

    /// Build once per render and pass it down — these projections categorize
    /// every visible row, and rebuilding the automaton per row would cost more
    /// than the matching does.
    static func matcher(from rows: [StoredCategoryRule]) -> CategoryMatcher {
        CategoryMatcher(rules: rules(from: rows))
    }

    /// UUIDs of bank rows confirmed as the bank-side copy of an app payment.
    static func matchedBankUUIDs(in matches: [StoredMatch]) -> Set<UUID> {
        Set(matches.map(\.bankUUID))
    }

    /// UUIDs of cross-bank self-transfer pairs (HDFC↔IDFC internal movements),
    /// plus the captured-alert rows that are legs of one — see
    /// `SelfTransfers.alerts`.
    static func selfTransferUUIDs(in txns: [StoredTransaction]) -> Set<UUID> {
        let bank = txns.filter { $0.source.kind == .bank }
        let flagged = SelfTransfers.detect(bank: bank.map {
            (ReconTxn(id: $0.uuid, date: $0.date, amountPaise: $0.amountPaise,
                      direction: $0.direction, reference: $0.reference), $0.source)
        })
        let bankRefs = Set(bank.filter { flagged.contains($0.uuid) }.compactMap(\.reference))
        let alerts = txns.filter { $0.source == .alert }.compactMap { txn in
            txn.reference.map { (id: txn.uuid, reference: $0, direction: txn.direction) }
        }
        return flagged.union(SelfTransfers.alerts(alerts, bankSelfTransferRefs: bankRefs))
    }

    /// The recorded history: every payment-app transaction, plus bank rows that have no
    /// app counterpart. Matched bank rows are reconciliation evidence, not records.
    static func visible(_ txns: [StoredTransaction], matches: [StoredMatch]) -> [StoredTransaction] {
        let matched = matchedBankUUIDs(in: matches)
        return txns.filter { !matched.contains($0.uuid) }
    }

    /// Counted analytics rows: visible history minus self transfers.
    ///
    /// `selfTransfers` is O(bank debits × bank credits) to derive, and a
    /// dashboard render needs it for both this projection and `insightRecords`.
    /// Pass it in to compute it once per render; nil recomputes it, which is
    /// what one-shot callers want.
    static func analytics(txns: [StoredTransaction], matches: [StoredMatch],
                          matcher: CategoryMatcher,
                          selfTransfers: Set<UUID>? = nil) -> [AnalyticsTxn] {
        let selfTransfers = selfTransfers ?? selfTransferUUIDs(in: txns)
        return visible(txns, matches: matches)
            .filter { !selfTransfers.contains($0.uuid) }
            .map { txn in
                AnalyticsTxn(month: txn.month,
                             amountPaise: txn.amountPaise,
                             direction: txn.direction,
                             category: effectiveCategory(of: txn, matcher: matcher, selfTransfers: []),
                             merchant: txn.counterparty,
                             sourceKind: txn.source.kind)
            }
    }

    /// Insight input: the same counted rows analytics uses, carrying the row
    /// id so a card can point back at its evidence. See `analytics` for why
    /// `selfTransfers` is injectable.
    static func insightRecords(_ txns: [StoredTransaction], matches: [StoredMatch],
                               matcher: CategoryMatcher,
                               selfTransfers: Set<UUID>? = nil) -> [InsightRecord] {
        let selfTransfers = selfTransfers ?? selfTransferUUIDs(in: txns)
        return visible(txns, matches: matches)
            .filter { !selfTransfers.contains($0.uuid) }
            .map { txn in
                InsightRecord(id: txn.uuid.uuidString,
                              date: txn.date,
                              amountPaise: txn.amountPaise,
                              direction: txn.direction,
                              category: effectiveCategory(of: txn, matcher: matcher,
                                                          selfTransfers: []),
                              merchant: txn.counterparty.isEmpty ? txn.narration
                                                                 : txn.counterparty)
            }
    }

    /// Pure counterpart of `suggestionRecords(_:)`, for views that already hold
    /// `@Query` rows. The context variant refetches, so a view built on it
    /// never refreshes — see the note at the top of this section.
    static func suggestionRecords(_ txns: [StoredTransaction], matches: [StoredMatch],
                                  matcher: CategoryMatcher,
                                  selfTransfers: Set<UUID>) -> [SpendRecord] {
        visible(txns, matches: matches).map { txn in
            SpendRecord(merchant: txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
                        amountPaise: txn.amountPaise,
                        date: txn.date,
                        direction: txn.direction,
                        effectiveCategory: effectiveCategory(of: txn, matcher: matcher,
                                                             selfTransfers: selfTransfers))
        }
    }

    /// Rows for `RuleImpact.affectedCount` — what a proposed rule would change.
    ///
    /// The population is `visible`, the recorded history: a matched bank row is
    /// reconciliation *evidence*, not a record, and is not shown anywhere the
    /// user could watch it change. Counting one would inflate the promise the
    /// offer makes.
    ///
    /// Both flags are filled from real data on purpose. `isSelfTransfer`
    /// defaults to `false`, and `effectiveCategory` labels a self transfer
    /// ahead of both the override and the matcher — so leaving the flag at its
    /// default silently counts every self transfer whose narration happens to
    /// carry the pattern, with nothing downstream to catch it.
    static func impactRows(_ txns: [StoredTransaction], matches: [StoredMatch],
                           selfTransfers: Set<UUID>) -> [RuleImpact.Row] {
        visible(txns, matches: matches).map { txn in
            RuleImpact.Row(text: "\(txn.counterparty) \(txn.narration)",
                           hasOverride: txn.categoryOverride != nil,
                           isSelfTransfer: selfTransfers.contains(txn.uuid))
        }
    }

    static func insightPeriods(_ documents: [StoredDocument]) -> [DatePeriod] {
        statements(documents).map(\.period)
    }

    static func grid(documents: [StoredDocument], pinned: [PinnedMonth]) -> CoverageGrid {
        CoverageGrid.derive(
            documents: statements(documents).map { DocumentSummary(id: $0.uuid, source: $0.source, period: $0.period) },
            pinnedMonths: Set(pinned.map(\.yearMonth)))
    }

    static func reconProjection(_ txns: [StoredTransaction],
                                month: YearMonth) -> (app: [ReconTxn], bank: [ReconTxn]) {
        let monthTxns = txns.filter { $0.month == month }
        func projected(_ kind: SourceKind) -> [ReconTxn] {
            monthTxns.filter { $0.source.kind == kind }
                .map { ReconTxn(id: $0.uuid, date: $0.date, amountPaise: $0.amountPaise,
                                direction: $0.direction, reference: $0.reference) }
        }
        return (projected(.paymentApp), projected(.bank))
    }

    // MARK: context-based variants (import pipeline and one-shot sheets)

    /// Display/analytics category. Bank-only rows fall back to Miscellaneous rather
    /// than Uncategorized; self transfers are labeled as such.
    static func effectiveCategory(of txn: StoredTransaction, matcher: CategoryMatcher,
                                  selfTransfers: Set<UUID>) -> String {
        if selfTransfers.contains(txn.uuid) { return Categorizer.selfTransfer }
        if let override = txn.categoryOverride { return override }
        let auto = matcher.category(for: "\(txn.counterparty) \(txn.narration)")
        if auto == Categorizer.uncategorized && txn.source.kind == .bank {
            return Categorizer.miscellaneous
        }
        return auto
    }

    /// Projection feeding SuggestionEngine: visible transactions (matched bank
    /// evidence excluded) with their effective categories.
    static func suggestionRecords(_ ctx: ModelContext) -> [SpendRecord] {
        let txns = allTransactions(ctx)
        let matcher = CategoryMatcher(rules: categoryRules(ctx))
        let selfTransfers = selfTransferUUIDs(in: txns)
        let matches = (try? ctx.fetch(FetchDescriptor<StoredMatch>())) ?? []
        return visible(txns, matches: matches).map { txn in
            SpendRecord(merchant: txn.counterparty.isEmpty ? txn.narration : txn.counterparty,
                        amountPaise: txn.amountPaise,
                        date: txn.date,
                        direction: txn.direction,
                        effectiveCategory: effectiveCategory(of: txn, matcher: matcher,
                                                             selfTransfers: selfTransfers))
        }
    }

    static func reconTxns(_ ctx: ModelContext, month: YearMonth) -> (app: [ReconTxn], bank: [ReconTxn]) {
        reconProjection(allTransactions(ctx), month: month)
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
        let selfTransfers = selfTransferUUIDs(in: allTransactions(ctx))
        let bank = rawBank.filter { !selfTransfers.contains($0.id) }
        guard !app.isEmpty, !bank.isEmpty else { return }
        let result = Reconciler.reconcile(app: app, bank: bank)
        for pair in result.matches {
            ctx.insert(StoredMatch(appUUID: pair.appID, bankUUID: pair.bankID, tier: pair.tier, month: month))
        }
    }
}
