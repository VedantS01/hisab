import AppIntents
import SwiftData
import HisabCore

/// Ingests one transaction alert from anywhere: a Shortcuts automation, the
/// share sheet, or Siri. Deliberately source-agnostic — Apple's richer
/// Notification trigger is iOS 27 only, and the iOS 17+ Message trigger's
/// body input is undocumented, so the design must not depend on either.
struct AddTransactionAlertIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction Alert"
    static let description = IntentDescription(
        "Reads a bank or UPI alert and files it for categorization. Nothing leaves your phone.")

    /// Never open the app: an automation must be able to run silently.
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Alert Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = HisabContainer.shared.mainContext

        guard var memo = AlertParser.parse(text: text, receivedAt: Date()) else {
            return .result(dialog: "No transaction found in that text.")
        }
        memo.note = note

        let inserted = MemoStore.insert(memo, into: ctx)
        CapturePrefs.lastCaptureAt = Date()

        guard inserted else {
            return .result(dialog: "Already logged \(Money.formatPaise(memo.amountPaise)).")
        }
        CaptureNotifier.considerNotifying(memo: memo, in: ctx)
        return .result(dialog: "Logged \(Money.formatPaise(memo.amountPaise)) to \(memo.payee).")
    }
}
