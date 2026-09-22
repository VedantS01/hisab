import SwiftUI
import SwiftData
import HisabCore

// MARK: - health

/// What the two capture timestamps say about whether capture is still working.
///
/// B4: one timestamp cannot tell "the automation never fired" from "the
/// automation fires and every parse fails", and those need OPPOSITE
/// remediations — go re-check your Shortcuts automation, versus nothing you can
/// do, wait for an update. A warning that confidently sends the user to fix a
/// working automation is worse than no warning at all, so the copy is driven by
/// both `lastAttemptAt` (every intent run) and `lastCaptureAt` (successful
/// parses only).
enum CaptureHealth: Equatable {
    /// Capture is off; the user is not owed a warning about it.
    case off
    /// Capture is on, nothing has arrived, and nothing ever has.
    case neverArrived
    /// Capture is on and nothing has arrived for `days` days.
    case noAlerts(days: Int)
    /// Alerts are arriving and none of them parse. Their setup is fine.
    case unreadable
    case healthy

    /// Three IST days: a weekend without a single bank alert is ordinary, four
    /// days without one is not.
    static let staleDays = 3

    static func evaluate(enabled: Bool, lastAttemptAt: Date?, lastCaptureAt: Date?,
                         now: Date) -> CaptureHealth {
        guard enabled else { return .off }
        guard let lastAttemptAt else { return .neverArrived }
        let sinceAttempt = ISTDay.daysBetween(lastAttemptAt, now)
        if sinceAttempt > staleDays { return .noAlerts(days: sinceAttempt) }
        guard let lastCaptureAt else { return .unreadable }
        return ISTDay.daysBetween(lastCaptureAt, now) > staleDays ? .unreadable : .healthy
    }

    var message: String? {
        switch self {
        case .off, .healthy:
            return nil
        case .neverArrived:
            return "No alerts have reached Hisab yet. The Shortcuts automation has to be built by hand — Hisab cannot install it for you."
        case .noAlerts(let days):
            return "No alerts received in \(days) days — the automation may have stopped."
        case .unreadable:
            return "Alerts are arriving but Hisab could not read them. Nothing on your side is broken; a bank has probably changed its message wording."
        }
    }

    /// Only the two states the user can actually act on link to the setup
    /// screen. `.unreadable` deliberately does not: their setup is fine.
    var offersSetup: Bool {
        switch self {
        case .neverArrived, .noAlerts: return true
        case .off, .unreadable, .healthy: return false
        }
    }

    static var current: CaptureHealth {
        evaluate(enabled: CapturePrefs.isEnabled,
                 lastAttemptAt: CapturePrefs.lastAttemptAt,
                 lastCaptureAt: CapturePrefs.lastCaptureAt,
                 now: Date())
    }
}

/// The dashboard's capture-health line.
///
/// Both timestamps live in UserDefaults, which is not observable — so, exactly
/// like `DashboardView.suppressions`, the value the body READS is `@State` and
/// is re-read on appear. A write-only version counter would create no
/// dependency in the attribute graph and would invalidate nothing.
struct CaptureHealthBanner: View {
    @State private var health = CaptureHealth.current

    var body: some View {
        if let message = health.message {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(message).font(.subheadline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HisabTheme.sona)
                }
                .foregroundStyle(HisabTheme.primaryText)
                if health.offersSetup {
                    NavigationLink("Check capture setup") { CaptureSetupView() }
                        .font(.subheadline.weight(.semibold))
                        .tint(HisabTheme.khataRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HisabTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("capture-health")
            .onAppear { refresh() }
        } else {
            Color.clear.frame(height: 0).onAppear { refresh() }
        }
    }

    private func refresh() {
        let current = CaptureHealth.current
        if current != health { health = current }
    }
}

// MARK: - the dashboard section

/// Captured alerts Hisab could not categorize, on the dashboard.
///
/// P4: fed by `@Query`, so a memo captured by the App Intent while the app is
/// open — or a category assigned from a notification button — shows up without
/// anything having to tell the view to look again.
///
/// P5: tapping a memo routes through `DeepLinkRouter` rather than presenting a
/// sheet here, so the review sheet has exactly ONE presentation path in the app
/// whether it was reached from a notification, a `hisab://` link or this list.
struct NeedsReviewSection: View {
    @Environment(DeepLinkRouter.self) private var router
    @Query(sort: \StoredPendingMemo.capturedAt, order: .reverse)
    private var memoRows: [StoredPendingMemo]

    private var pending: [StoredPendingMemo] {
        memoRows.filter { $0.mergedTxnUUID == nil && $0.assignedCategory == nil }
    }

    var body: some View {
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Needs review")
                        .font(.headline)
                        .foregroundStyle(HisabTheme.primaryText)
                    Spacer()
                    Text("\(pending.count)")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(HisabTheme.khataRed, in: Capsule())
                        .foregroundStyle(HisabTheme.kagaz)
                        .accessibilityIdentifier("needs-review-count")
                }
                ForEach(pending.prefix(5), id: \.captureHash) { memo in
                    Button {
                        router.pendingMemoHash = memo.captureHash
                    } label: {
                        MemoRow(memo: memo)
                    }
                    .buttonStyle(.plain)
                    // A `.plain` button hit-tests only what it DRAWS, so the
                    // gap a `Spacer` leaves between the payee and the amount —
                    // most of the row — was not tappable. Caught by a tap at
                    // the row's centre doing nothing at all.
                    .contentShape(Rectangle())
                }
                if pending.count > 5 {
                    Button("See all \(pending.count)") { router.showNeedsReview = true }
                        .font(.subheadline)
                        .tint(HisabTheme.khataRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HisabTheme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("needs-review-section")
        }
    }
}

struct MemoRow: View {
    let memo: StoredPendingMemo
    /// Off inside a `NavigationLink`, which draws its own.
    var showsChevron = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.payee)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HisabTheme.primaryText)
                    .lineLimit(1)
                Text(ISTStamp.dayTime(memo.capturedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HisabTheme.amountText(memo.amountPaise, direction: memo.direction)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - the inbox

/// Where a `hisab://` link with nothing to resolve lands, and where "See all"
/// goes. A real list, never a blank screen.
struct NeedsReviewInbox: View {
    /// Set when the user arrived through `hisab://transaction/<uuid>` and no
    /// such transaction exists (P9) — said plainly rather than dropped.
    var missingTransaction: UUID?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredPendingMemo.capturedAt, order: .reverse)
    private var memoRows: [StoredPendingMemo]

    private var pending: [StoredPendingMemo] {
        memoRows.filter { $0.mergedTxnUUID == nil && $0.assignedCategory == nil }
    }

    var body: some View {
        NavigationStack {
            List {
                if missingTransaction != nil {
                    Section {
                        Text("That link points at a transaction Hisab no longer has — it may have been erased with its statement.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if pending.isEmpty {
                        Text("Nothing waiting. Captured alerts Hisab cannot categorize show up here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pending, id: \.captureHash) { memo in
                            NavigationLink {
                                MemoReviewContent(captureHash: memo.captureHash)
                            } label: {
                                MemoRow(memo: memo, showsChevron: false)
                            }
                        }
                    }
                } header: {
                    Text("Needs review")
                }
                Section {
                    NavigationLink("Capture setup") { CaptureSetupView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(HisabTheme.background)
            .navigationTitle("Needs review")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("needs-review-inbox")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - the transaction deep link

/// P9: `hisab://transaction/<uuid>` used to land on a raw UUID string. It now
/// opens the transaction's own detail sheet — the same one the Transactions tab
/// presents — and falls back to the inbox, explaining itself, when the row is
/// gone.
///
/// P4: the lookup is over a `@Query`, not a `ModelContext` fetch, so the sheet
/// tracks an edit made to the row while it is open. The scan is linear over
/// rows the app already keeps in memory for the dashboard, which is why it is a
/// filter rather than a `#Predicate`.
struct TransactionRouteSheet: View {
    let uuid: UUID
    @Query private var txnRows: [StoredTransaction]

    var body: some View {
        if let txn = txnRows.first(where: { $0.uuid == uuid }) {
            TxnDetailSheet(txn: txn)
        } else {
            NeedsReviewInbox(missingTransaction: uuid)
        }
    }
}
