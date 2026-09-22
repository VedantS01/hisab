import SwiftUI
import SwiftData
import UserNotifications
import HisabCore
#if DEBUG
import Darwin
#endif

@main
struct HisabApp: App {
    /// One router for the process: the notification delegate writes to the same
    /// object `RootView.body` reads, which is the whole point of it being
    /// `@Observable` rather than a plain value someone forgets to publish.
    @State private var router: DeepLinkRouter
    /// `UNUserNotificationCenter.delegate` is weak, so the app has to own this.
    private let notificationDelegate: CaptureNotificationDelegate

    init() {
        let router = DeepLinkRouter()
        let delegate = CaptureNotificationDelegate(router: router)
        _router = State(initialValue: router)
        notificationDelegate = delegate
        // Must be set before the app finishes launching, or a notification that
        // launched the app is delivered to nobody.
        UNUserNotificationCenter.current().delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .onOpenURL { router.handle($0) }
        }
        .modelContainer(HisabContainer.shared)
    }
}

/// Turns a notification response into router state and, for a category button,
/// into a stored categorization plus a pending rule offer.
///
/// Deliberately NOT `@MainActor`: `UNUserNotificationCenterDelegate` is
/// nonisolated and its arguments are non-Sendable ObjC classes, so an isolated
/// conformance does not compile under Swift 6. The delegate therefore copies
/// the two values it needs out of the response and hops to the main actor,
/// where the SwiftData writes and the router mutation belong.
final class CaptureNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// `@MainActor` types are implicitly Sendable, so holding the reference
    /// here is safe; touching it is only legal on the main actor.
    private let router: DeepLinkRouter

    init(router: DeepLinkRouter) {
        self.router = router
        super.init()
    }

    /// Without this, a notification arriving while Hisab is open is delivered
    /// silently — including every notification in a simulator verification run,
    /// which would make a working feature look broken.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let actionID = response.actionIdentifier
        let hash = response.notification.request.content.userInfo["captureHash"] as? String
        let router = self.router
        // `nonisolated(unsafe)` is sound here specifically because UN delegate
        // callbacks arrive on the main thread and the `Task { @MainActor }`
        // below resumes there too: the closure is created and invoked on the
        // same thread, so nothing non-Sendable actually crosses a boundary.
        // Do not copy this opt-out anywhere that is not true.
        nonisolated(unsafe) let finish = completionHandler
        Task { @MainActor in
            CaptureNotifier.respond(actionID: actionID, captureHash: hash,
                                    router: router,
                                    in: HisabContainer.shared.mainContext)
            finish()
        }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var router
    @State private var selectedTab = "dashboard"
    @State private var suggestion: RuleSuggestion?

    private struct SuggestionItem: Identifiable {
        let suggestion: RuleSuggestion
        var id: String { suggestion.merchantPattern }
    }

    /// Reads — not merely writes — the router. If this ever becomes a write-only
    /// reference again, the deep link and the notification tap both go silently
    /// dead, exactly as 1.2's dismiss/mute did.
    private var isRouted: Bool {
        router.pendingMemoHash != nil || router.pendingTxnUUID != nil || router.showNeedsReview
    }

    var body: some View {
        // Read in `body` itself, not inside the sheet's `Binding` getter. The
        // getter is a closure SwiftUI happens to evaluate inside its
        // observation scope, so presentation would rest on that; reading here
        // puts the router's properties in this view's dependency set directly,
        // leaving no mechanism by which a change could fail to re-render.
        // (The neighbouring suggestion sheet uses the same `Binding` shape but
        // is backed by `@State`, where any mutation invalidates the view
        // regardless of what `body` read. It is not precedent for this case.)
        let routed = isRouted
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
            // Simulator-only: capture is off by default and its toggle lands in
            // Settings with task 11, so there is otherwise no way to reach the
            // launch-time authorization request below.
            if args.contains("--capture-enable") { CapturePrefs.isEnabled = true }
            #endif
            // Authorization is requested when the user turns capture ON (task
            // 11's Settings toggle) and again here whenever capture is already
            // on, because iOS returns the existing answer without re-prompting.
            // Without it, UNUserNotificationCenter.add fails SILENTLY: no error
            // at the call site, no notification, and no clue which of the two
            // it was.
            if CapturePrefs.isEnabled { await CaptureNotifier.requestAuthorization() }
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
            // Simulator-only: reports what the notification system actually did.
            // A missing banner has two indistinguishable causes — an unanswered
            // permission prompt and a categorize-guard that returned early — and
            // only the authorization status plus the scheduled/delivered lists
            // tell them apart. Runs last, after any --capture-alert above.
            if args.contains("--capture-notify-report") {
                await printNotificationReport()
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
        .sheet(isPresented: Binding(
            get: { routed },
            set: { if !$0 { router.clear() } }
        )) {
            CaptureRouteSheet(memoHash: router.pendingMemoHash,
                              txnUUID: router.pendingTxnUUID)
        }
    }

    #if DEBUG
    private func printNotificationReport() async {
        // The cap and `notifiedAt` are now written from `add`'s completion
        // handler, which lands asynchronously. Without this wait the report can
        // read the store before a SUCCESSFUL send has been recorded and make a
        // working send look like a suppressed one — the exact confusion this
        // harness exists to remove.
        try? await Task.sleep(for: .milliseconds(750))
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let categories = await center.notificationCategories()
        func describe(_ content: UNNotificationContent, id: String) -> String {
            "\(id)|\(content.title)|\(content.body)|\(content.categoryIdentifier)"
        }
        // `sentToday` and `notifiedAt` are what prove the negative case: when
        // the add fails (permission declined), neither the daily cap nor the
        // memo may record a banner that was never shown.
        let memos = MemoStore.all(context).sorted { $0.captureHash < $1.captureHash }
        let notifiedAt = memos.map { memo in
            memo.notifiedAt.map { "\(memo.captureHash.prefix(8))=\($0.timeIntervalSince1970)" }
                ?? "\(memo.captureHash.prefix(8))=nil"
        }
        print("debug-notify: auth=\(settings.authorizationStatus.rawValue) "
            + "alert=\(settings.alertSetting.rawValue) "
            + "sentToday=\(CapturePrefs.notificationsSentToday(now: Date())) "
            + "notifiedAt=\(notifiedAt) "
            + "pending=\(pending.map { describe($0.content, id: $0.identifier) }) "
            + "delivered=\(delivered.map { describe($0.request.content, id: $0.request.identifier) }) "
            + "registered=\(categories.map { cat in "\(cat.identifier)->\(cat.actions.map(\.identifier))" })")
        fflush(stdout)
    }
    #endif
}

/// Interim destination for a `hisab://` link and for a notification tap.
///
/// Task 11 replaces this with `MemoReviewSheet` and `NeedsReviewSection`. It
/// exists now because router state that nothing renders is precisely the
/// write-only bug this task is meant to avoid, and because this task's own
/// verification has nothing to observe without a reader.
///
/// Deliberately NOT wrapped in `#if DEBUG`: until task 11 lands, a release
/// build still needs *something* to render the route, and a router nothing
/// renders is the worse failure. The deprecation is a compile-time tripwire
/// instead — every use site warns until this type is deleted.
@available(*, deprecated,
            message: "Interim scaffold — Task 11 must delete this and route to MemoReviewSheet")
struct CaptureRouteSheet: View {
    let memoHash: String?
    let txnUUID: UUID?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var memo: StoredPendingMemo? {
        memoHash.flatMap { MemoStore.find(hash: $0, in: context) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let memo {
                    memoDetail(memo)
                } else {
                    inbox
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func memoDetail(_ memo: StoredPendingMemo) -> some View {
        List {
            LabeledContent("Amount", value: Money.formatPaise(memo.amountPaise))
            LabeledContent("Payee", value: memo.payee)
            LabeledContent("Captured", value: memo.capturedAt.formatted(date: .abbreviated,
                                                                        time: .shortened))
            LabeledContent("Category", value: memo.assignedCategory ?? "—")
            if let offer = CaptureNotifier.pendingRuleOffer, offer.captureHash == memo.captureHash {
                LabeledContent("Rule offer", value: offer.category)
            }
        }
        .navigationTitle("Review memo")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("capture-route-memo")
    }

    /// Where an unresolvable link lands — a real list, not a blank screen.
    private var inbox: some View {
        List {
            if let txnUUID {
                Section("Transaction") { Text(txnUUID.uuidString) }
            }
            Section("Needs review") {
                let pending = MemoStore.pending(context)
                if pending.isEmpty {
                    Text("Nothing waiting.").foregroundStyle(.secondary)
                } else {
                    ForEach(pending, id: \.captureHash) { memo in
                        VStack(alignment: .leading) {
                            Text(Money.formatPaise(memo.amountPaise))
                            Text(memo.payee).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Needs review")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("capture-route-inbox")
    }
}
