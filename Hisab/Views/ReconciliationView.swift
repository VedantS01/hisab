import SwiftUI
import SwiftData
import HisabCore

struct ReconciliationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredTransaction.date, order: .reverse) private var allTxns: [StoredTransaction]
    @Query private var matchRows: [StoredMatch]
    @State private var month: YearMonth

    init(initialMonth: YearMonth) {
        _month = State(initialValue: initialMonth)
    }

    var body: some View {
        List {
            let monthTxns = allTxns.filter { $0.month == month }
            let byUUID = Dictionary(uniqueKeysWithValues: monthTxns.map { ($0.uuid, $0) })
            let (app, bank) = Queries.reconProjection(allTxns, month: month)
            let matches = matchRows.filter { $0.monthKey == month.description }
            let matchedApp = Set(matches.map(\.appUUID))
            let matchedBank = Set(matches.map(\.bankUUID))

            Section {
                Picker("Month", selection: $month) {
                    ForEach(Set(allTxns.map(\.month)).sorted(by: >), id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .pickerStyle(.menu)
            }

            if app.isEmpty || bank.isEmpty {
                Section {
                    Text(app.isEmpty
                         ? "No payment-app transactions for \(month.displayName) yet."
                         : "No bank statement for \(month.displayName) yet — reconciliation runs once both sides exist.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Matched (\(matches.count))") {
                    ForEach(matches, id: \.appUUID) { match in
                        if let appTxn = byUUID[match.appUUID] {
                            HStack {
                                TxnRow(txn: appTxn)
                                Text(match.tier == .reference ? "ref" : "±date")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(HisabTheme.hara.opacity(0.15), in: Capsule())
                                    .foregroundStyle(HisabTheme.hara)
                            }
                        }
                    }
                }
                let appOnly = app.filter { !matchedApp.contains($0.id) }
                Section("App payments missing from bank (\(appOnly.count))") {
                    if appOnly.isEmpty {
                        Text("None — every app payment shows in the bank.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(appOnly, id: \.id) { txn in
                        if let stored = byUUID[txn.id] {
                            TxnRow(txn: stored)
                                .listRowBackground(HisabTheme.khataRed.opacity(0.06))
                        }
                    }
                }
                let bankOnly = bank.filter { !matchedBank.contains($0.id) }
                Section("Bank-only spending (\(bankOnly.count))") {
                    if bankOnly.isEmpty {
                        Text("None").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(bankOnly, id: \.id) { txn in
                        if let stored = byUUID[txn.id] {
                            TxnRow(txn: stored)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HisabTheme.background)
        .navigationTitle("Reconciliation")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Queries.recomputeMatches(context, month: month)
                    try? context.save()
                } label: {
                    Label("Recompute", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}
