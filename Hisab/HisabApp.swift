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
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.bar.doc.horizontal") {
                DashboardView()
            }
            Tab("Buckets", systemImage: "calendar") {
                BucketsView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle") {
                TransactionsView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .tint(HisabTheme.khataRed)
    }
}
