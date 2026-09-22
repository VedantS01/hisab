import Foundation
import Observation

/// Where a `hisab://` link wants the UI to go. Observable so SwiftUI actually
/// re-renders — a write-only value that `body` never reads is the exact bug
/// that shipped in 1.2's dismiss/mute.
@MainActor
@Observable
final class DeepLinkRouter {
    var pendingMemoHash: String?
    var pendingTxnUUID: UUID?
    var showNeedsReview = false

    /// Bumped by `CaptureNotifier.respond` whenever a category button queues a
    /// rule offer. The offers themselves live in UserDefaults, which is not
    /// observable; this is the observable edge that tells a running app to look
    /// again. Not part of `clear()` — it is a change counter, not a
    /// destination, and resetting it would re-fire the reader.
    var ruleOfferGeneration = 0

    /// `hisab://memo/<captureHash>` or `hisab://transaction/<uuid>`.
    /// An unrecognised or unresolvable link opens the needs-review inbox
    /// rather than failing silently.
    func handle(_ url: URL) {
        guard url.scheme == "hisab" else { return }
        let value = url.lastPathComponent
        switch url.host {
        // Each branch clears the sibling field: this type's whole job is to say
        // where the UI should go, and a second link arriving with no
        // intervening dismiss (which would have run `clear()`) must not leave
        // it saying two things at once.
        case "memo":
            pendingMemoHash = value.isEmpty ? nil : value
            pendingTxnUUID = nil
            showNeedsReview = value.isEmpty
        case "transaction":
            pendingTxnUUID = UUID(uuidString: value)
            pendingMemoHash = nil
            showNeedsReview = pendingTxnUUID == nil
        default:
            // Clears the siblings for the same reason the other two branches
            // do, which this branch did not. It was invisible while the interim
            // scaffold rendered both fields at once; now that `RootView` picks
            // ONE destination by precedence, an unrecognised link arriving on
            // top of a live memo or transaction route was simply swallowed —
            // the state still said "show the memo", and the link did nothing.
            pendingMemoHash = nil
            pendingTxnUUID = nil
            showNeedsReview = true
        }
    }

    /// Clears everything the sheet was opened for. Called when the sheet is
    /// dismissed, so a second identical link re-opens it instead of being
    /// swallowed by state that is already set.
    func clear() {
        pendingMemoHash = nil
        pendingTxnUUID = nil
        showNeedsReview = false
    }
}
