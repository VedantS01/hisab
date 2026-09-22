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

    /// `hisab://memo/<captureHash>` or `hisab://transaction/<uuid>`.
    /// An unrecognised or unresolvable link opens the needs-review inbox
    /// rather than failing silently.
    func handle(_ url: URL) {
        guard url.scheme == "hisab" else { return }
        let value = url.lastPathComponent
        switch url.host {
        case "memo":
            pendingMemoHash = value.isEmpty ? nil : value
            showNeedsReview = value.isEmpty
        case "transaction":
            pendingTxnUUID = UUID(uuidString: value)
            showNeedsReview = pendingTxnUUID == nil
        default:
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
