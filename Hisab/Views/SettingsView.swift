import SwiftUI
import SwiftData
import HisabCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredCategoryRule.sortOrder) private var rules: [StoredCategoryRule]
    @Query private var pins: [PinnedMonth]
    @State private var showAddRule = false
    @State private var eraseArmed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rules, id: \.uuid) { rule in
                        HStack {
                            Text(rule.pattern).font(.subheadline.monospaced())
                            Spacer()
                            Text(rule.category).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        var reordered = rules
                        reordered.move(fromOffsets: from, toOffset: to)
                        for (index, rule) in reordered.enumerated() {
                            rule.sortOrder = index
                        }
                        try? context.save()
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            context.delete(rules[offset])
                        }
                        try? context.save()
                    }
                    Button {
                        showAddRule = true
                    } label: {
                        Label("Add rule", systemImage: "plus")
                    }
                } header: {
                    Text("Category rules")
                } footer: {
                    Text("First matching rule wins — drag to reorder priority. Rules match case-insensitively against merchant and narration.")
                }

                Section("Pinned months") {
                    if pins.isEmpty {
                        Text("None — pin months from the Buckets tab.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(pins, id: \.persistentModelID) { pin in
                        Text(pin.yearMonth.displayName)
                    }
                    .onDelete { offsets in
                        for offset in offsets {
                            context.delete(pins[offset])
                        }
                        try? context.save()
                    }
                }

                Section {
                    Button("Erase all data", role: .destructive) {
                        eraseArmed = true
                    }
                } footer: {
                    Text("Hisab keeps everything on this device only. Erasing removes all imported documents, transactions and matches.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    Link("github.com/VedantS01/hisab", destination: URL(string: "https://github.com/VedantS01/hisab")!)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddRule) {
                AddRuleSheet(nextOrder: rules.count)
            }
            .confirmationDialog("Erase ALL Hisab data? This cannot be undone.",
                                isPresented: $eraseArmed, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func eraseAll() {
        try? context.delete(model: StoredMatch.self)
        try? context.delete(model: StoredTransaction.self)
        try? context.delete(model: StoredDocument.self)
        try? context.delete(model: PinnedMonth.self)
        try? context.delete(model: StoredCategoryRule.self)
        try? context.save()
        let imports = URL.documentsDirectory.appending(path: "imports")
        try? FileManager.default.removeItem(at: imports)
    }
}

struct AddRuleSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let nextOrder: Int
    @State private var pattern = ""
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Pattern (e.g. dominos)", text: $pattern)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Category (e.g. Food Delivery)", text: $category)
            }
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(StoredCategoryRule(pattern: pattern, category: category, sortOrder: nextOrder))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(pattern.isEmpty || category.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
