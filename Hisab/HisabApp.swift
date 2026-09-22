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
    /// Rule offers queued by a notification's category button, presented in
    /// turn (P6). Mirrors `CaptureNotifier.pendingRuleOffers`, which lives in
    /// UserDefaults and cannot be observed; `router.ruleOfferGeneration` is the
    /// observable edge that says when to re-read it.
    @State private var ruleOffers: [CaptureNotifier.RuleOffer] = []

    /// The ONE thing this view can be presenting.
    ///
    /// P5: the suggestion prompt and the capture route used to be two `.sheet`
    /// modifiers on this same `TabView`. On a cold launch from a notification
    /// tap on a day the daily suggestion had not yet shown, both bindings
    /// became true in a single update and SwiftUI presented one and silently
    /// dropped the other — and the one it dropped was the one the user had just
    /// tapped. One `.sheet(item:)` over an enum makes that unrepresentable: the
    /// destinations are now ordered rather than racing.
    enum Destination: Identifiable {
        case memo(String)
        case transaction(UUID)
        case needsReview
        case ruleOffer(CaptureNotifier.RuleOffer)
        case suggestion(RuleSuggestion)

        var id: String {
            switch self {
            case .memo(let hash): "memo|\(hash)"
            case .transaction(let uuid): "txn|\(uuid.uuidString)"
            case .needsReview: "needs-review"
            case .ruleOffer(let offer): "offer|\(offer.captureHash)|\(offer.category)"
            case .suggestion(let suggestion): "suggestion|\(suggestion.merchantPattern)"
            }
        }
    }

    /// Reads — not merely writes — the router. If this ever becomes a write-only
    /// reference again, the deep link and the notification tap both go silently
    /// dead, exactly as 1.2's dismiss/mute did.
    ///
    /// Order is precedence, and it is deliberate: something the user just
    /// tapped outranks a queued offer, which outranks the once-a-day prompt
    /// nobody asked for. Whatever loses is not discarded — it is still in the
    /// state this reads, so it presents as soon as the winner is dismissed.
    private var destination: Destination? {
        if let hash = router.pendingMemoHash { return .memo(hash) }
        if let uuid = router.pendingTxnUUID { return .transaction(uuid) }
        if router.showNeedsReview { return .needsReview }
        if let offer = ruleOffers.first { return .ruleOffer(offer) }
        if let suggestion { return .suggestion(suggestion) }
        return nil
    }

    var body: some View {
        // Read in `body` itself, not inside the sheet's `Binding` getter. The
        // getter is a closure SwiftUI happens to evaluate inside its
        // observation scope, so presentation would rest on that; reading here
        // puts the router's properties in this view's dependency set directly,
        // leaving no mechanism by which a change could fail to re-render.
        // (The suggestion and the queued offers are `@State`, where any
        // mutation invalidates the view regardless of what `body` read. The
        // router's properties are not, which is why they are read here.)
        let destination = self.destination
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
            // The other half of the pair, and the only way to observe P1: the
            // flag lives in UserDefaults and survives a reinstall-free relaunch,
            // so a run that wants capture OFF has to say so rather than assume
            // the default still holds.
            // Goes through `setEnabled`, not the raw flag, so the harness
            // exercises the disable path the Settings toggle takes — I5's
            // cancellation of already-queued notifications included.
            if args.contains("--capture-disable") { await CaptureNotifier.setEnabled(false) }
            // Simulator-only: backdates the two health timestamps, e.g.
            //   --capture-backdate 10 10   (nothing has arrived for 10 days)
            //   --capture-backdate 0 10    (arriving, none of it parses)
            // B4's three health states are otherwise unreachable in a
            // verification run: `lastAttemptAt` is written only by the intent,
            // and a simulator shares the host clock, so there is no way to be
            // three days later. Takes effect on the NEXT launch's render, since
            // the banner reads on appear.
            if let index = args.firstIndex(of: "--capture-backdate"),
               args.indices.contains(index + 2),
               let attemptDays = Int(args[index + 1]),
               let captureDays = Int(args[index + 2]) {
                let day = 86_400.0
                CapturePrefs.lastAttemptAt = Date().addingTimeInterval(-Double(attemptDays) * day)
                CapturePrefs.lastCaptureAt = Date().addingTimeInterval(-Double(captureDays) * day)
            }
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
                printCaptureState()
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
                printCaptureState()
                fflush(stdout)
            }
            // Simulator-only: drives one notification RESPONSE through the real
            // `CaptureNotifier.respond`, e.g.
            //   --capture-respond 'CAT|Groceries' <hash>   (a category button)
            //   --capture-respond MEMO_LATER <hash>        (the Later button)
            // Three of `respond`'s four branches were unobserved (P9) and the
            // simulator cannot be made to tap a real banner's buttons, so this
            // is the only way to exercise them — and the only way to prove I5's
            // gate, which is the difference between a store write and no store
            // write after the toggle goes off.
            for (index, arg) in args.enumerated() where arg == "--capture-respond" {
                guard args.indices.contains(index + 2) else { continue }
                CaptureNotifier.respond(actionID: args[index + 1],
                                        captureHash: args[index + 2],
                                        router: router, in: context)
                printCaptureState()
                fflush(stdout)
            }
            // Simulator-only: the blast-radius measurement B2 asks for.
            //   --capture-rule-impact <pattern> <category>
            // Prints the number the offer WOULD show, then writes the rule
            // through the same helper the offer's button uses and counts the
            // rows whose effective category really changed. Both numbers come
            // from one run over one store, so they are comparable by
            // construction rather than by two readings lining up.
            for (index, arg) in args.enumerated() where arg == "--capture-rule-impact" {
                guard args.indices.contains(index + 2) else { continue }
                printRuleImpact(pattern: args[index + 1], category: args[index + 2])
            }
            // Simulator-only: parks one request in the system's PENDING queue,
            // so I5's cancellation has something to cancel.
            //
            // The real producer of a pending request is the quiet-hours `.hold`
            // branch, which only fires between 22:00 and 08:00 IST — a window a
            // verification run cannot enter, since a simulator shares the host
            // clock. This stands in for it: same API, same queue, a trigger far
            // enough out that it cannot fire mid-run. It is a PROBE, not a
            // reproduction of the hold path.
            if args.contains("--capture-schedule-probe") {
                let content = UNMutableNotificationContent()
                content.title = "Probe"
                content.body = "Stands in for a quiet-hours hold."
                let request = UNNotificationRequest(
                    identifier: "capture-probe", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600,
                                                               repeats: false))
                try? await UNUserNotificationCenter.current().add(request)
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
            // The launch-time read of the offer queue. `onChange` below only
            // catches an offer queued while this app is already running; a
            // category button tapped on a lock-screen banner queued it in a
            // process that has since been killed, which is the normal case.
            ruleOffers = CaptureNotifier.pendingRuleOffers
            if !SuggestionSchedule.alreadyShownToday {
                suggestion = SuggestionEngine.queue(records: Queries.suggestionRecords(context),
                                                    now: Date(),
                                                    muted: SuggestionSchedule.muted).first
            }
        }
        .sheet(item: Binding(
            get: { destination },
            set: { newValue in
                // A dismissal clears only what was actually on screen, so the
                // next-highest destination can take its turn rather than being
                // swept away with it.
                guard newValue == nil else { return }
                switch destination {
                case .memo, .transaction, .needsReview:
                    router.clear()
                case .ruleOffer(let offer):
                    CaptureNotifier.clearOffer(captureHash: offer.captureHash)
                    ruleOffers = CaptureNotifier.pendingRuleOffers
                case .suggestion:
                    suggestion = nil
                    SuggestionSchedule.markShown()
                case nil:
                    break
                }
            }
        )) { destination in
            switch destination {
            case .memo(let hash):
                MemoReviewSheet(captureHash: hash)
            case .transaction(let uuid):
                TransactionRouteSheet(uuid: uuid)
            case .needsReview:
                NeedsReviewInbox()
            case .ruleOffer(let offer):
                RuleOfferSheet(offer: offer) {
                    ruleOffers = CaptureNotifier.pendingRuleOffers
                }
            case .suggestion(let suggestion):
                SuggestionPrompt(suggestion: suggestion)
            }
        }
        .onChange(of: router.ruleOfferGeneration) { _, _ in
            ruleOffers = CaptureNotifier.pendingRuleOffers
        }
    }

    #if DEBUG
    /// The store and the two health timestamps in one line.
    ///
    /// `enabled` and `lastAttemptAt` are what prove P1: with capture off the
    /// memo count must NOT move while `lastAttemptAt` must, because an alert
    /// that arrived and was refused is still an arrival. Printing them together
    /// with the memo list makes the two observations one reading rather than
    /// two that could have come from different launches.
    private func printCaptureState() {
        let memos = MemoStore.all(context).sorted { $0.captureHash < $1.captureHash }
        func stamp(_ date: Date?) -> String {
            date.map { String(format: "%.2f", $0.timeIntervalSince1970) } ?? "nil"
        }
        let offers = CaptureNotifier.pendingRuleOffers
            .map { "\($0.captureHash.prefix(8))=\($0.category)" }
        // One real transaction id, so `hisab://transaction/<uuid>` can be aimed
        // at a row that exists. Nothing else in the app prints one, and P9's
        // success branch is otherwise unobservable from a launch argument.
        let sampleTxn = Queries.allTransactions(context).first
            .map { "\($0.uuid.uuidString)|\($0.counterparty)" } ?? "none"
        print("debug-capture: enabled=\(CapturePrefs.isEnabled) "
            + "memos=\(memos.count) hashes=\(memos.map(\.captureHash)) "
            + "categories=\(memos.map { $0.assignedCategory ?? "nil" }) "
            + "offers=\(offers) sampleTxn=\(sampleTxn) "
            + "router=memo:\(router.pendingMemoHash ?? "nil"),"
            + "txn:\(router.pendingTxnUUID?.uuidString ?? "nil"),"
            + "inbox:\(router.showNeedsReview) "
            + "lastAttemptAt=\(stamp(CapturePrefs.lastAttemptAt)) "
            + "lastCaptureAt=\(stamp(CapturePrefs.lastCaptureAt))")
    }

    /// The offered count and the real one, measured in a single pass.
    ///
    /// `offered` is what `MemoReviewSheet` would put in the sentence. `changed`
    /// is counted afterwards by re-deriving every visible row's effective
    /// category with the rule in place and comparing it to the same row's
    /// category before — the app's own read-time categorization, not a second
    /// implementation of it. `naive` is the same count with `isSelfTransfer`
    /// forced to false, which is what a caller that built rows straight from
    /// `StoredTransaction` would get; when it exceeds `offered`, the gap is
    /// exactly the over-count the flag exists to prevent.
    private func printRuleImpact(pattern: String, category: String) {
        let txns = Queries.allTransactions(context)
        let matches = (try? context.fetch(FetchDescriptor<StoredMatch>())) ?? []
        let selfTransfers = Queries.selfTransferUUIDs(in: txns)
        let ruleRows = (try? context.fetch(FetchDescriptor<StoredCategoryRule>(
            sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let rules = Queries.rules(from: ruleRows)
        let rows = Queries.impactRows(txns, matches: matches, selfTransfers: selfTransfers)
        let offered = RuleImpact.affectedCount(pattern: pattern, category: category,
                                               rows: rows, rules: rules)
        let naive = RuleImpact.affectedCount(
            pattern: pattern, category: category,
            rows: rows.map { RuleImpact.Row(text: $0.text, hasOverride: $0.hasOverride,
                                            isSelfTransfer: false) },
            rules: rules)

        let visible = Queries.visible(txns, matches: matches)
        func categories(_ matcher: CategoryMatcher, _ rows: [StoredTransaction]) -> [String] {
            rows.map { Queries.effectiveCategory(of: $0, matcher: matcher,
                                                 selfTransfers: selfTransfers) }
        }
        let beforeVisible = categories(Queries.matcher(from: ruleRows), visible)
        let beforeAll = categories(Queries.matcher(from: ruleRows), txns)

        RuleOffers.createRule(pattern: pattern, category: category,
                              existing: ruleRows, in: context)

        let afterRuleRows = (try? context.fetch(FetchDescriptor<StoredCategoryRule>(
            sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let afterMatcher = Queries.matcher(from: afterRuleRows)
        let changed = zip(beforeVisible, categories(afterMatcher, visible))
            .count { $0 != $1 }
        // The same count over EVERY row, matched bank evidence included, so a
        // disagreement between the two populations is visible rather than
        // assumed away.
        let changedAll = zip(beforeAll, categories(afterMatcher, txns)).count { $0 != $1 }
        print("debug-impact: pattern=\(pattern) category=\(category) "
            + "offered=\(offered) changed=\(changed) naive=\(naive) "
            + "changedAllRows=\(changedAll) visible=\(visible.count) all=\(txns.count)")
        fflush(stdout)
    }

    private func printNotificationReport() async {
        // CORRECTED (task 11a fix round 1): this wait is NOT about our own
        // writes any more. `considerNotifying` now does `try await center.add`
        // and then records the cap and `notifiedAt` in straight-line main-actor
        // code, so by the time it returns those two are already durable.
        //
        // What the wait protects against is the notification daemon's own
        // registration lag: `pendingNotificationRequests()` and
        // `deliveredNotifications()` do not reflect an accepted `add`
        // instantly, so a report taken immediately can show an empty pending
        // list for a banner that was scheduled — the exact confusion this
        // harness exists to remove. Do not delete it on the grounds that the
        // async writes are gone; that is a different reason and it has gone.
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
