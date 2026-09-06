import SwiftUI
import SwiftData
import HisabCore

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredTransaction.date, order: .reverse) private var allTxns: [StoredTransaction]
    @Query private var matchRows: [StoredMatch]
    @Query(sort: \StoredCategoryRule.sortOrder) private var ruleRows: [StoredCategoryRule]
    @State private var monthFilter: YearMonth?
    @State private var sourceFilter: Source?
    @State private var categoryFilter: String?
    @State private var unmatchedOnly = false
    @State private var detailTxn: StoredTransaction?

    var body: some View {
        NavigationStack {
            List {
                let rules = Queries.rules(from: ruleRows)
                let selfTransfers = Queries.selfTransferUUIDs(in: allTxns)
                let txns = filtered(rules: rules, selfTransfers: selfTransfers)
                if txns.isEmpty {
                    if hasActiveFilters {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("No transactions match the active filters.")
                                .foregroundStyle(.secondary)
                            Button("Clear filters") { clearFilters() }
                                .tint(HisabTheme.khataRed)
                        }
                    } else {
                        Text("No transactions yet — import a statement from the Dashboard.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(txns, id: \.uuid) { txn in
                        Button {
                            detailTxn = txn
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                TxnRow(txn: txn)
                                HStack(spacing: 6) {
                                    categoryChip(Queries.effectiveCategory(of: txn, rules: rules,
                                                                           selfTransfers: selfTransfers))
                                    if unmatchedSet.contains(txn.uuid) {
                                        Text("unmatched")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(HisabTheme.khataRed.opacity(0.14), in: Capsule())
                                            .foregroundStyle(HisabTheme.khataRed)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HisabTheme.background)
            .navigationTitle("Transactions")
            .toolbar { filterMenu }
            .sheet(item: $detailTxn) { txn in
                TxnDetailSheet(txn: txn)
            }
        }
    }

    private var hasActiveFilters: Bool {
        monthFilter != nil || sourceFilter != nil || categoryFilter != nil || unmatchedOnly
    }

    private func clearFilters() {
        monthFilter = nil
        sourceFilter = nil
        categoryFilter = nil
        unmatchedOnly = false
    }

    private var filterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Month", selection: $monthFilter) {
                    Text("All months").tag(YearMonth?.none)
                    ForEach(availableMonths, id: \.self) { month in
                        Text(month.displayName).tag(YearMonth?.some(month))
                    }
                }
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag(Source?.none)
                    ForEach(Source.allCases) { source in
                        Text(source.displayName).tag(Source?.some(source))
                    }
                }
                Picker("Category", selection: $categoryFilter) {
                    Text("All categories").tag(String?.none)
                    ForEach(availableCategories, id: \.self) { category in
                        Text(category).tag(String?.some(category))
                    }
                }
                Toggle("Unmatched only", isOn: $unmatchedOnly)
                if hasActiveFilters {
                    Divider()
                    Button("Clear filters", role: .destructive) { clearFilters() }
                }
            } label: {
                Label("Filter", systemImage: hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
            }
        }
    }

    private var availableMonths: [YearMonth] {
        Set(allTxns.map(\.month)).sorted(by: >)
    }

    private var availableCategories: [String] {
        let rules = Queries.rules(from: ruleRows)
        let selfTransfers = Queries.selfTransferUUIDs(in: allTxns)
        let cats = Set(Queries.visible(allTxns, matches: matchRows)
            .map { Queries.effectiveCategory(of: $0, rules: rules, selfTransfers: selfTransfers) })
        return cats.sorted()
    }

    /// App-side transactions in reconciled months that no bank row matched.
    private var unmatchedSet: Set<UUID> {
        var result = Set<UUID>()
        let matchedApp = Set(matchRows.map(\.appUUID))
        for month in availableMonths {
            let (app, bank) = Queries.reconProjection(allTxns, month: month)
            guard !app.isEmpty, !bank.isEmpty else { continue }
            for txn in app where !matchedApp.contains(txn.id) {
                result.insert(txn.id)
            }
        }
        return result
    }

    private func filtered(rules: [CategoryRule], selfTransfers: Set<UUID>) -> [StoredTransaction] {
        var txns = Queries.visible(allTxns, matches: matchRows)
        if let monthFilter { txns = txns.filter { $0.month == monthFilter } }
        if let sourceFilter { txns = txns.filter { $0.source == sourceFilter } }
        if let categoryFilter {
            txns = txns.filter {
                Queries.effectiveCategory(of: $0, rules: rules, selfTransfers: selfTransfers) == categoryFilter
            }
        }
        if unmatchedOnly {
            let unmatched = unmatchedSet
            txns = txns.filter { unmatched.contains($0.uuid) }
        }
        return txns
    }

    private func categoryChip(_ category: String) -> some View {
        Text(category)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(HisabTheme.sona.opacity(0.15), in: Capsule())
            .foregroundStyle(HisabTheme.primaryText)
    }
}

struct TxnDetailSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let txn: StoredTransaction
    @State private var selectedCategory = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    row("Merchant", txn.counterparty)
                    row("Date", txn.date.formatted(.dateTime.day().month().year()))
                    HStack {
                        Text("Amount").foregroundStyle(.secondary)
                        Spacer()
                        HisabTheme.amountText(txn.amountPaise, direction: txn.direction)
                    }
                    row("Source", txn.source.displayName)
                    if let ref = txn.reference { row("Reference", ref) }
                }
                Section("Narration") {
                    Text(txn.narration).font(.caption.monospaced())
                }
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                    }
                    if txn.categoryOverride != nil {
                        Button("Reset to automatic") {
                            txn.categoryOverride = nil
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let rules = Queries.categoryRules(context)
                        let automatic = Categorizer.category(for: "\(txn.counterparty) \(txn.narration)", rules: rules)
                        txn.categoryOverride = selectedCategory == automatic ? nil : selectedCategory
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedCategory = Queries.category(of: txn, rules: Queries.categoryRules(context))
            }
        }
    }

    private var allCategories: [String] {
        let rules = Queries.categoryRules(context)
        var cats = Set(rules.map(\.category))
        cats.insert(Categorizer.uncategorized)
        cats.insert(selectedCategory)
        return cats.sorted()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
