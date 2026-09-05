import SwiftUI
import SwiftData
import HisabCore

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedMonth = YearMonth(date: Date())
    @State private var showImport = false
    @State private var refreshToken = 0
    @State private var pushRecon = false

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
            .background(HisabTheme.background)
            .navigationTitle("Hisab")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImport = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(isPresented: $showImport, onDismiss: { refreshToken += 1 }) {
                ImportSheet()
            }
            .navigationDestination(isPresented: $pushRecon) {
                ReconciliationView(initialMonth: selectedMonth)
            }
            .task {
                if ProcessInfo.processInfo.arguments.contains("--push-recon") {
                    try? await Task.sleep(for: .seconds(1))
                    pushRecon = true
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let txns = Queries.analyticsTxns(context)
        let grid = Queries.coverageGrid(context)
        let _ = refreshToken

        if txns.isEmpty {
            emptyState
        } else {
            VStack(spacing: 16) {
                MonthChipRow(months: monthOptions(grid: grid), selected: $selectedMonth)
                HeroCard(stats: Analytics.monthStats(txns, month: selectedMonth),
                         previous: Analytics.monthStats(txns, month: selectedMonth.advanced(by: -1)))
                TrendChart(trend: Analytics.trend(txns, endingAt: selectedMonth, count: 6),
                           selected: selectedMonth)
                CoverageStrip(grid: grid, month: selectedMonth)
                ReconHealthCard(month: selectedMonth)
                CategoryBars(breakdown: Analytics.categoryBreakdown(txns, month: selectedMonth, top: 5))
                MerchantList(merchants: Analytics.topMerchants(txns, month: selectedMonth, top: 5))
                RecentTxns(month: selectedMonth)
            }
            .padding(.top, 8)
        }
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

    private func monthOptions(grid: CoverageGrid) -> [YearMonth] {
        grid.months.isEmpty ? [YearMonth(date: Date())] : grid.months
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
