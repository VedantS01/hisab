import SwiftUI
import SwiftData
import HisabCore

struct DocumentListSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let month: YearMonth
    let source: Source
    let documentIDs: [UUID]
    @State private var deleteTarget: StoredDocument?

    var body: some View {
        NavigationStack {
            List {
                ForEach(fetchDocuments(), id: \.uuid) { doc in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.filename)
                            .font(.subheadline.weight(.medium))
                        Text("\(doc.period.months.first?.displayName ?? "?") – \(doc.period.months.last?.displayName ?? "?") · \(doc.transactions?.count ?? 0) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("imported \(doc.importedAt.formatted(.dateTime.day().month().year()))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            deleteTarget = doc
                        }
                    }
                }
            }
            .navigationTitle("\(source.displayName) · \(month.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete this document and its transactions?",
                                isPresented: Binding(get: { deleteTarget != nil },
                                                     set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let doc = deleteTarget {
                        delete(doc)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func fetchDocuments() -> [StoredDocument] {
        let all = (try? context.fetch(FetchDescriptor<StoredDocument>())) ?? []
        return all.filter { documentIDs.contains($0.uuid) }
    }

    private func delete(_ doc: StoredDocument) {
        let months = doc.period.months
        context.delete(doc)   // cascades to its transactions
        try? context.save()
        for month in months {
            Queries.recomputeMatches(context, month: month)
        }
        try? context.save()
        dismiss()
    }
}
