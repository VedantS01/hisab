import SwiftUI
import SwiftData
import HisabCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredCategoryRule.sortOrder) private var rules: [StoredCategoryRule]
    @Query private var pins: [PinnedMonth]
    @State private var showAddRule = false
    @State private var editTarget: StoredCategoryRule?
    @State private var eraseArmed = false
    /// UserDefaults is not observable, so these mirror it and are re-read in
    /// `.task` — the same shape `DashboardView.suppressions` uses.
    @State private var captureEnabled = CapturePrefs.isEnabled
    @State private var captureHealth = CaptureHealth.current
    @State private var lastCaptureAt = CapturePrefs.lastCaptureAt
    @State private var authorization = UNAuthorizationStatusBox.unknown

    var body: some View {
        NavigationStack {
            List {
                // First, not after the rule table: that table is ~85 seed rows
                // deep, so a capture section below it is off-screen by a full
                // screen or more — which is where the toggle a user goes to
                // Settings to find would have been.
                captureSection

                Section {
                    ForEach(rules, id: \.uuid) { rule in
                        Button {
                            editTarget = rule
                        } label: {
                            HStack {
                                Text(rule.pattern).font(.subheadline.monospaced())
                                Spacer()
                                Text(rule.category).font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
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
                    Text("Tap a rule to edit it. First matching rule wins — drag to reorder priority. Rules match case-insensitively against merchant and narration; edits re-categorize existing transactions automatically.")
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
                    Button("Load demo data") {
                        DemoData.load(into: context)
                    }
                } footer: {
                    Text("Fills seven months of synthetic GPay, HDFC and IDFC statements so you can explore Hisab. Tapping again replaces the demo with a fresh copy. Erase any time.")
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
            .scrollContentBackground(.hidden)
            .background(HisabTheme.background)
            .navigationTitle("Settings")
            .task { await refreshCapture() }
            .sheet(isPresented: $showAddRule) {
                RuleEditorSheet(rule: nil, nextOrder: rules.count,
                                existingCategories: distinctCategories)
            }
            .sheet(item: $editTarget) { rule in
                RuleEditorSheet(rule: rule, nextOrder: rules.count,
                                existingCategories: distinctCategories)
            }
            .confirmationDialog("Erase ALL Hisab data? This cannot be undone.",
                                isPresented: $eraseArmed, titleVisibility: .visible) {
                Button("Erase everything", role: .destructive) { eraseAll() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// The capture toggle, its health line, and the way to the setup screen.
    ///
    /// The toggle goes through `CaptureNotifier.setEnabled`, never through
    /// `CapturePrefs.isEnabled` directly: turning capture off has to cancel the
    /// notifications already queued (I5), and turning it on has to ask for
    /// notification permission the first time (P1). Writing the flag here would
    /// silently skip both.
    @ViewBuilder
    private var captureSection: some View {
        Section {
            Toggle("Capture bank alerts", isOn: $captureEnabled)
                .tint(HisabTheme.khataRed)
                .accessibilityIdentifier("capture-toggle")
                .onChange(of: captureEnabled) { _, newValue in
                    Task {
                        await CaptureNotifier.setEnabled(newValue)
                        await refreshCapture()
                    }
                }
            if captureEnabled {
                LabeledContent("Last captured",
                               value: lastCaptureAt.map(ISTStamp.dayTime) ?? "Never")
                    .accessibilityIdentifier("capture-last")
                if authorization == .denied {
                    Label("Notifications are off for Hisab, so it cannot ask what an unknown payment was. Turn them on in iOS Settings › Notifications › Hisab.",
                          systemImage: "bell.slash")
                        .font(.footnote)
                        .foregroundStyle(HisabTheme.khataRed)
                }
                if let message = captureHealth.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("capture-health-line")
                }
            }
            NavigationLink("Capture setup") { CaptureSetupView() }
        } header: {
            Text("Alert capture")
        } footer: {
            Text("Hands a bank or UPI alert to Hisab through a Shortcuts automation you build yourself. Captured alerts are memos, not ledger entries — your statements stay the source of truth. Nothing leaves this phone.")
        }
    }

    private func refreshCapture() async {
        captureEnabled = CapturePrefs.isEnabled
        lastCaptureAt = CapturePrefs.lastCaptureAt
        captureHealth = CaptureHealth.current
        authorization = UNAuthorizationStatusBox(await CaptureNotifier.authorizationStatus())
    }

    private var distinctCategories: [String] {
        Set(rules.map(\.category)).sorted()
    }

    private func eraseAll() {
        try? context.delete(model: StoredMatch.self)
        try? context.delete(model: StoredTransaction.self)
        try? context.delete(model: StoredDocument.self)
        try? context.delete(model: PinnedMonth.self)
        try? context.delete(model: StoredCategoryRule.self)
        try? context.save()
        // Suppressions are keyed by insight id and merchant key; surviving an
        // erase would silently hide cards about data the user no longer has.
        InsightStore.clearAll()
        let imports = URL.documentsDirectory.appending(path: "imports")
        try? FileManager.default.removeItem(at: imports)
    }
}

struct RuleEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let rule: StoredCategoryRule?   // nil creates a new rule
    let nextOrder: Int
    let existingCategories: [String]
    @State private var pattern = ""
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Pattern (e.g. dominos)", text: $pattern)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section("Category") {
                    TextField("Category (e.g. Food Delivery)", text: $category)
                    if !existingCategories.isEmpty {
                        Menu("Use an existing category") {
                            ForEach(existingCategories, id: \.self) { name in
                                Button(name) { category = name }
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
            .navigationTitle(rule == nil ? "New rule" : "Edit rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let rule {
                            rule.pattern = pattern
                            rule.category = category
                        } else {
                            context.insert(StoredCategoryRule(pattern: pattern, category: category,
                                                              sortOrder: nextOrder))
                        }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(pattern.isEmpty || category.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let rule {
                    pattern = rule.pattern
                    category = rule.category
                }
            }
        }
        .presentationDetents([.medium])
    }
}
