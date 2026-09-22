import SwiftUI
import SwiftData
import HisabCore
#if DEBUG
import Darwin
#endif

@main
struct HisabApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(HisabContainer.shared)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedTab = "dashboard"
    @State private var suggestion: RuleSuggestion?

    private struct SuggestionItem: Identifiable {
        let suggestion: RuleSuggestion
        var id: String { suggestion.merchantPattern }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.doc.horizontal", value: "dashboard") {
                DashboardView()
            }
            Tab("Buckets", systemImage: "calendar", value: "buckets") {
                BucketsView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle", value: "transactions") {
                TransactionsView()
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                SettingsView()
            }
        }
        .tint(HisabTheme.khataRed)
        .task {
            _ = Queries.categoryRules(context)  // seed defaults on first launch
            let args = ProcessInfo.processInfo.arguments
            #if DEBUG
            // Puts the store in the state a pre-1.2 user upgrades with: a demo
            // imported under the old byte-hash identity. See DemoData.
            if args.contains("--seed-legacy-demo") {
                DemoData.loadLegacyForTesting(into: context)
            }
            #endif
            if args.contains("--seed-demo") {
                // `--demo-now yyyy-MM-dd` anchors the demo's month shift to a
                // day other than today, so a test can put the simulator in the
                // state a user reaches by loading the demo and coming back next
                // month.
                let anchor = args.firstIndex(of: "--demo-now").flatMap { index in
                    args.indices.contains(index + 1)
                        ? ISTDay.date(from: args[index + 1]) : nil
                }
                DemoData.load(into: context, now: anchor ?? Date())
            }
            #if DEBUG
            // Simulator-only harness: import real statement files straight from the
            // host filesystem, e.g. --pw 1234 --import /path/a.pdf --import /path/b.xlsx
            let password = args.firstIndex(of: "--pw").flatMap { i in
                args.indices.contains(i + 1) ? args[i + 1] : nil
            }
            let service = ImportService(context: context)
            for (index, arg) in args.enumerated() where arg == "--import" {
                guard args.indices.contains(index + 1) else { continue }
                let url = URL(fileURLWithPath: args[index + 1])
                let report = try? service.importFile(at: url, password: password, overrideSource: nil)
                print("debug-import \(url.lastPathComponent): \(report.map { "\($0.newCount) new of \($0.totalParsed)" } ?? "FAILED")")
            }
            #endif
            if let index = args.firstIndex(of: "--tab"), args.indices.contains(index + 1) {
                selectedTab = args[index + 1]
            }
            #if DEBUG
            if args.contains("--force-suggestion") { SuggestionSchedule.resetForDebug() }
            #endif
            #if DEBUG
            // Simulator-only: drives one alert through the real App Intent, so the
            // dedup guard can be proven against the real store. UI automation cannot
            // reach the Shortcuts app here, and MemoStore has no unit-test target.
            for (index, arg) in args.enumerated() where arg == "--capture-alert" {
                guard args.indices.contains(index + 1) else { continue }
                let intent = AddTransactionAlertIntent()
                intent.text = args[index + 1]
                _ = try? await intent.perform()
                let memos = MemoStore.all(context).sorted { $0.captureHash < $1.captureHash }
                print("debug-capture: memos=\(memos.count) hashes=\(memos.map(\.captureHash)) categories=\(memos.map { $0.assignedCategory ?? "nil" })")
                // simctl's --console-pipe attaches to the app's real stdout, which is
                // fully-buffered (not line-buffered) once it's a pipe rather than a
                // tty; without an explicit flush the line above sits in libc's buffer
                // and is lost when simctl terminate kills the process before it exits
                // normally. This flush is harness-only debug plumbing, not a change to
                // the intent's own behaviour.
                fflush(stdout)
            }
            // Simulator-only: assigns a category to the single most recently
            // captured memo, so a follow-up --capture-alert run can prove (or
            // disprove) that a duplicate capture preserves it rather than
            // silently reverting it via SwiftData's unique-attribute upsert.
            for (index, arg) in args.enumerated() where arg == "--capture-assign" {
                guard args.indices.contains(index + 1) else { continue }
                if let target = MemoStore.pending(context).first {
                    MemoStore.assign(category: args[index + 1], to: target, in: context)
                }
                let memos = MemoStore.all(context).sorted { $0.captureHash < $1.captureHash }
                print("debug-capture: memos=\(memos.count) hashes=\(memos.map(\.captureHash)) categories=\(memos.map { $0.assignedCategory ?? "nil" })")
                fflush(stdout)
            }
            #endif
            if !SuggestionSchedule.alreadyShownToday {
                suggestion = SuggestionEngine.queue(records: Queries.suggestionRecords(context),
                                                    now: Date(),
                                                    muted: SuggestionSchedule.muted).first
            }
        }
        .sheet(item: Binding(
            get: { suggestion.map(SuggestionItem.init) },
            set: { if $0 == nil { suggestion = nil } }
        ), onDismiss: { SuggestionSchedule.markShown() }) { item in
            SuggestionPrompt(suggestion: item.suggestion)
        }
    }
}
