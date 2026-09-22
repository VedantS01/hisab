import AppIntents

/// Surfaces the intent in the Shortcuts app and Siri without setup.
struct HisabShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddTransactionAlertIntent(),
                    phrases: ["Add a transaction alert to \(.applicationName)",
                              "Log a payment in \(.applicationName)"],
                    shortTitle: "Add Alert",
                    systemImageName: "indianrupeesign.circle")
    }
}
