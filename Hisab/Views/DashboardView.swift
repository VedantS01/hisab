import SwiftUI
import SwiftData
import HisabCore

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredTransaction.date, order: .reverse) private var storedTxns: [StoredTransaction]
    @Query private var storedDocs: [StoredDocument]
    @Query private var pins: [PinnedMonth]
    @Query private var matchRows: [StoredMatch]
    @Query(sort: \StoredCategoryRule.sortOrder) private var ruleRows: [StoredCategoryRule]
    @State private var selectedMonth = YearMonth(date: Date())
    @State private var showImport = false
    @State private var pushRecon = false
    @State private var openInsight: Insight?
    /// Re-read after every dismiss/mute: UserDefaults writes (where
    /// suppressions live) aren't Observable, so nothing else would tell
    /// SwiftUI to look again. It has to be the value the body *reads* — a
    /// write-only version counter creates no dependency in the attribute
    /// graph, so bumping one never invalidates anything (it didn't).
    @State private var suppressions = InsightStore.suppressions

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .background(HisabTheme.background)
            .navigationTitle("हिसाब")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                ImportSheet()
            }
            .sheet(item: $openInsight) { insight in
                InsightEvidenceSheet(insight: insight, transactions: storedTxns)
            }
            .navigationDestination(isPresented: $pushRecon) {
                ReconciliationView(initialMonth: selectedMonth)
            }
            .onAppear {
                // Settings' "Erase all data" clears the suppression keys, and
                // UserDefaults writes aren't Observable — without this re-read
                // the dashboard would keep suppressing against the wiped set
                // until the app restarted. Guarded so an unchanged value
                // doesn't invalidate the body on every tab switch.
                let current = InsightStore.suppressions
                if current != suppressions { suppressions = current }
            }
            .task {
                let args = ProcessInfo.processInfo.arguments
                if let index = args.firstIndex(of: "--month"), args.indices.contains(index + 1) {
                    let parts = args[index + 1].split(separator: "-").compactMap { Int($0) }
                    if parts.count == 2 { selectedMonth = YearMonth(year: parts[0], month: parts[1]) }
                }
                if args.contains("--reset-insights") {
                    InsightStore.resetForDebug()
                    suppressions = InsightStore.suppressions
                }
                if args.contains("--push-recon") {
                    try? await Task.sleep(for: .seconds(1))
                    pushRecon = true
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let matcher = Queries.matcher(from: ruleRows)
        // Derived once and handed to both projections: detecting self
        // transfers compares every bank debit against every bank credit, and
        // `content` runs on every body pass.
        let selfTransfers = Queries.selfTransferUUIDs(in: storedTxns)
        let txns = Queries.analytics(txns: storedTxns, matches: matchRows,
                                     matcher: matcher, selfTransfers: selfTransfers)
        let grid = Queries.grid(documents: storedDocs, pinned: pins)
        // Recomputed every time `content` runs, including after `suppressions`
        // is re-read — see its declaration.
        let insightResult = InsightsEngine.generate(
            input: InsightsInput(
                records: Queries.insightRecords(storedTxns, matches: matchRows,
                                                matcher: matcher,
                                                selfTransfers: selfTransfers),
                documentPeriods: Queries.insightPeriods(storedDocs),
                now: Date()),
            config: InsightsConfig.cached,
            suppressions: suppressions)

        // Capture health and the needs-review inbox sit ABOVE the empty-state
        // branch on purpose: a user who relies on capture and has imported
        // nothing yet is exactly the person with memos waiting and no
        // transactions, and putting them inside the `else` would hide the
        // feature from its own core audience.
        VStack(spacing: 16) {
            CaptureHealthBanner()
            NeedsReviewSection()
            if txns.isEmpty {
                emptyState
            } else {
                InsightStrip(insights: insightResult.cards,
                             onOpen: { openInsight = $0 },
                             onDismiss: { insight in
                                 InsightStore.dismiss(insight.id)
                                 suppressions = InsightStore.suppressions
                             },
                             onMute: { insight in
                                 if let target = insight.mute { InsightStore.mute(target) }
                                 suppressions = InsightStore.suppressions
                             })
                // Prunes stale dismissals against this pass's live id set.
                // `.task(id:)` reruns whenever the id set's *value* changes
                // (and once on first appearance) without a separate @State
                // mirror of it, so there's no window where a stale/empty
                // copy could be used — the guard below is still kept as a
                // hard backstop against ever intersecting with {}.
                .task(id: insightResult.allIDs) {
                    guard !insightResult.allIDs.isEmpty else { return }
                    InsightStore.prune(keeping: insightResult.allIDs)
                }
                MonthChipRow(months: monthOptions(grid: grid), selected: $selectedMonth)
                HeroCard(stats: Analytics.monthStats(txns, month: selectedMonth),
                         previous: Analytics.monthStats(txns, month: selectedMonth.advanced(by: -1)),
                         bankVerified: grid.sources.filter { $0.kind == .bank }.contains {
                             if case .present = grid.state(month: selectedMonth, source: $0) { return true }
                             return false
                         })
                TrendChart(trend: Analytics.trend(txns, endingAt: selectedMonth, count: 6),
                           selected: selectedMonth)
                CoverageStrip(grid: grid, month: selectedMonth)
                ReconHealthCard(month: selectedMonth)
                CategoryBars(breakdown: Analytics.categoryBreakdown(txns, month: selectedMonth, top: 5))
                MerchantList(merchants: Analytics.topMerchants(txns, month: selectedMonth, top: 5))
                RecentTxns(month: selectedMonth)
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 56))
                .foregroundStyle(HisabTheme.khataRed)
            Text("Your bahi-khata is empty")
                .font(.title2.weight(.semibold))
                .foregroundStyle(HisabTheme.primaryText)
            Text("Import a Google Pay or Paytm export, or an HDFC/IDFC bank statement, and Hisab will sort every month out for you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Import your first statement") {
                showImport = true
            }
            .buttonStyle(.borderedProminent)
            .tint(HisabTheme.khataRed)
        }
        .padding(.top, 100)
        .padding(.horizontal, 24)
    }

    /// The grid's months plus every month a captured alert falls in: the grid
    /// is statement coverage only, and the current month has to be selectable
    /// before its statement exists. Gap-filled, newest first, like the grid.
    private func monthOptions(grid: CoverageGrid) -> [YearMonth] {
        let months = Set(grid.months).union(storedTxns.filter { $0.source == .alert }.map(\.month))
        guard let lo = months.min(), let hi = months.max() else { return [YearMonth(date: Date())] }
        return YearMonth.months(from: lo, through: hi).reversed()
    }
}

struct MonthChipRow: View {
    let months: [YearMonth]
    @Binding var selected: YearMonth

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(months, id: \.self) { month in
                    Button {
                        selected = month
                    } label: {
                        Text(month.displayName)
                            .font(.subheadline.weight(month == selected ? .bold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(month == selected ? HisabTheme.khataRed : HisabTheme.cardBackground,
                                        in: Capsule())
                            .foregroundStyle(month == selected ? HisabTheme.kagaz : HisabTheme.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
