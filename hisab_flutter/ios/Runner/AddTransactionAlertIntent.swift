import AppIntents

/// Ingests one transaction alert from anywhere: a Shortcuts automation, the
/// share sheet, or Siri. Deliberately source-agnostic — Apple's richer
/// Notification trigger is iOS 27 only, and the iOS 17+ Message trigger's
/// body input is undocumented, so the design must not depend on either.
///
/// The type name, title and parameters are exactly the Swift app's (1.x):
/// Shortcuts stores automations against them, and renaming any of them would
/// silently break every automation users have already built.
struct AddTransactionAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction Alert"
    static let description = IntentDescription(
        "Reads a bank or UPI alert and files it for categorization. Nothing leaves your phone.")

    /// Never open the app: an automation must be able to run silently.
    static let openAppWhenRun: Bool = false

    /// Connects to the previous result so an automation's Shortcut Input (the
    /// message) can wire in without the user hunting for the field.
    @Parameter(title: "Alert Text",
               inputOptions: String.IntentInputOptions(multiline: true),
               inputConnectionBehavior: .connectToPreviousIntentResult)
    var text: String

    @Parameter(title: "Note")
    var note: String?

    /// Puts Alert Text inline in the action as a tappable token. Without a
    /// summary Shortcuts tucks it into a collapsed list, and an automation
    /// left with it empty cannot run silently.
    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Hisab") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await CaptureBridge.shared.ingest(text: text, note: note)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

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
