import SwiftUI
import HisabCore

/// Every card answers "show me why": the rows behind the number, or for the
/// committed-spend card, the recurring series that make it up.
struct InsightEvidenceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let insight: Insight
    let transactions: [StoredTransaction]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(insight.headline).font(.headline)
                    Text(insight.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if insight.kind == .committedSpend {
                    Section("Recurring payments") {
                        ForEach(insight.series, id: \.merchantKey) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayMerchant)
                                Text("\(Money.formatPaise(entry.medianPaise)) "
                                     + (entry.cadence == .monthly ? "per month" : "per week")
                                     + " · since \(YearMonth(date: entry.firstSeen).displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section("Transactions") {
                        ForEach(evidence, id: \.uuid) { txn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(txn.counterparty.isEmpty ? txn.narration : txn.counterparty)
                                        .lineLimit(1)
                                    Text(txn.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.formatPaise(txn.amountPaise))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Why this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var evidence: [StoredTransaction] {
        let wanted = Set(insight.evidenceIDs)
        return transactions
            .filter { wanted.contains($0.uuid.uuidString) }
            .sorted { $0.date > $1.date }
    }
}
