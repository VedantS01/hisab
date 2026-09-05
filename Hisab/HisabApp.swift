import SwiftUI
import SwiftData
import HisabCore

@main
struct HisabApp: App {
    let container: ModelContainer = {
        let schema = Schema([StoredDocument.self, StoredTransaction.self,
                             StoredCategoryRule.self, StoredMatch.self, PinnedMonth.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var selectedTab = "dashboard"

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
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--seed-demo") {
                DemoData.load(into: context)
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
        }
    }
}
