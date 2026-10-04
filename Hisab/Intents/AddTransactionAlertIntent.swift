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
        let ctx = HisabContainer.shared.mainContext

        // Unconditional, and BEFORE both the enable gate and the parse: an
        // alert that arrived while capture was off is still an arrival, and
        // health's whole job is to tell "nothing is reaching Hisab" apart from
        // "everything reaches Hisab and none of it parses".
        CapturePrefs.lastAttemptAt = Date()

        // P1: the Settings toggle has to actually stop capture. A toggle that
        // only silences the notification while memos keep accruing is worse
        // than no toggle — the user believes they switched the feature off.
        guard CapturePrefs.isEnabled else {
            return .result(dialog: "Capture is off. Turn it on in Hisab's settings.")
        }

        let outcome = CaptureService.capture(text, note: note, receivedAt: Date(), in: ctx)
        let results = [outcome.memo?.result, outcome.row?.result].compactMap { $0 }
        guard !results.isEmpty else {
            return .result(dialog: "No transaction found in that text.")
        }
        // Memo and row carry the same amount; the memo's payee is the name the
        // user knows, the row's counterparty the fallback when there is no memo.
        let amount = Money.formatPaise(outcome.memo?.memo.amountPaise ?? outcome.row?.row.amountPaise ?? 0)
        let payee = outcome.memo?.memo.payee ?? outcome.row?.row.counterparty ?? ""

        if results.contains(.inserted) {
            CapturePrefs.lastCaptureAt = Date()
            if let captured = outcome.memo, captured.result == .inserted {
                await CaptureNotifier.considerNotifying(memo: captured.memo, in: ctx)
            }
            let logged = payee.isEmpty ? "Logged \(amount)" : "Logged \(amount) to \(payee)"
            if outcome.row?.result == .inserted {
                return .result(dialog: "\(logged) and added it to your ledger.")
            }
            return .result(dialog: "\(logged).")
        }
        if results.contains(.failed) {
            // M-6: a store that could not be read or written is NOT a
            // duplicate. Saying "already logged" here would promise the user
            // their spend is filed when nothing was written, and refreshing
            // `lastCaptureAt` would paint the broken store healthy in Settings
            // — the one place that would otherwise show something is wrong.
            return .result(dialog: "Hisab couldn't save that alert. Nothing was stored.")
        }
        // A recognized repeat still proves the pipeline works end to end.
        CapturePrefs.lastCaptureAt = Date()
        return .result(dialog: "Already logged \(amount).")
    }
}
