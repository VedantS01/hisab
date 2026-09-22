import Foundation
import SwiftData
import UserNotifications
import HisabCore
#if DEBUG
import Darwin
#endif

@MainActor
enum CaptureNotifier {
    static let categoryPrefix = "MEMO_CATEGORIZE"
    static let laterActionID = "MEMO_LATER"
    /// Prefix of an action id carrying a category name. The remainder is the
    /// category verbatim — see `category(fromActionID:)`.
    static let categoryActionPrefix = "CAT|"

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Notifies only when Hisab could NOT categorize the payee — precisely the
    /// memory-decay case this feature exists for.
    ///
    /// `async` because of the authorization check below, which is the only
    /// reliable way to know whether a banner can be delivered at all.
    static func considerNotifying(memo: PendingMemo, in ctx: ModelContext) async {
        // P1: capture off means capture off, notifications included.
        guard CapturePrefs.isEnabled else { return }

        // P10: `add` does NOT report an error when authorization is denied —
        // observed directly in task 10's fix round, against the opposite
        // assumption. At `.denied` the request silently vanishes; at
        // `.notDetermined` it can even turn up in `deliveredNotifications()`.
        // So the completion-handler guard further down, though correct, closes
        // nothing on its own: without this check a user who declined the
        // prompt burns one of the day's ten slots and has the memo stamped
        // `notifiedAt` for a banner that never existed.
        //
        // Deliberately `.authorized` only, not `.provisional`: nothing here
        // ever requests provisional authorization (`requestAuthorization` asks
        // for `[.alert, .sound, .badge]`), so treating it as a send would be
        // untested speculation. If provisional is ever adopted, this is the
        // line to revisit.
        //
        // `alertSetting` is checked for the same reason and against the same
        // harm: a user who granted permission and then turned off Lock Screen,
        // Notification Center and Banners sits at `.authorized` with
        // `alertSetting == .disabled`. `add` accepts the request, no banner is
        // ever drawn, and without this the memo still burns one of the day's
        // ten slots and is stamped `notifiedAt` — P10 reached through a
        // different Settings toggle. Sound and badge alone are not the feature:
        // the whole point is a banner with category buttons on it.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized,
              settings.alertSetting != .disabled else {
            #if DEBUG
            print("debug-notify: suppressed, "
                + "authorizationStatus=\(settings.authorizationStatus.rawValue) "
                + "alertSetting=\(settings.alertSetting.rawValue)")
            fflush(stdout)
            #endif
            return
        }

        // P7: `notifiedAt` is read here, which is what makes writing it
        // legitimate. A field written and never read is exactly how the 1.2
        // dismiss/mute bug survived a review.
        //
        // NARROWED (fix round 2, F4): what this covers is RE-ENTRY into
        // `considerNotifying` for a memo that was not re-inserted — the
        // quiet-hours retry, where a held memo is reconsidered and must not be
        // scheduled a second time. It is NOT the standing guarantee the comment
        // used to claim for "any future capture path that does not dedup":
        // `captureHash` is `@Attribute(.unique)`, so a duplicate insert UPSERTS,
        // and `StoredPendingMemo.init(memo:)` does not copy `notifiedAt` — a
        // non-dedup path re-inserting the same hash would reset the field to nil
        // and this guard would silently not fire. Any such path must therefore
        // preserve `notifiedAt` across the upsert for this guard to mean
        // anything at all.
        if let stored = MemoStore.find(hash: memo.captureHash, in: ctx),
           stored.notifiedAt != nil {
            return
        }

        let rules = Queries.categoryRules(ctx)
        let matcher = CategoryMatcher(rules: rules)
        let auto = matcher.category(for: memo.payee)
        guard auto == Categorizer.uncategorized || auto == Categorizer.miscellaneous else {
            return
        }

        let now = Date()
        let decision = NotificationPolicy.decide(
            now: now, sentToday: CapturePrefs.notificationsSentToday(now: now))
        let fireDate: Date?
        switch decision {
        case .suppress: return
        case .send: fireDate = nil
        case .hold(let until): fireDate = until
        }

        let choices = CategoryRanker.topCategories(
            records: Queries.suggestionRecords(ctx), now: now, limit: 3)
        let categoryID = register(choices: choices)

        let content = UNMutableNotificationContent()
        content.title = "What was this?"
        content.body = "\(Money.formatPaise(memo.amountPaise)) to \(memo.payee)"
        content.categoryIdentifier = categoryID
        content.userInfo = ["captureHash": memo.captureHash]
        content.sound = .default

        var trigger: UNNotificationTrigger?
        if let fireDate {
            let interval = max(1, fireDate.timeIntervalSince(now))
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }

        let request = UNNotificationRequest(identifier: memo.captureHash,
                                            content: content, trigger: trigger)
        let captureHash = memo.captureHash
        // Only a request the system actually ACCEPTED may spend the daily
        // budget or stamp the memo — recording regardless would be the app
        // lying to itself about work it did not do. CORRECTED (task 11a): the
        // declined-permission case does NOT arrive here. Task 10's fix round
        // observed `add` returning no error at `.denied`, which is why the
        // authorization check at the top of this function exists. This catch
        // covers a genuine scheduling refusal only, and no way has been found
        // to provoke one on a simulator, so the branch stays unexercised.
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // A1 exists because this failure is otherwise invisible: no banner,
            // and no clue whether the cause was permission or scheduling.
            #if DEBUG
            print("debug-notify: add FAILED for \(captureHash): "
                + "\(error.localizedDescription)")
            fflush(stdout)
            #endif
            return
        }

        // Straight-line after the `await`, and already on the main actor: both
        // writes happen before this function returns, so no caller can observe
        // a successful send that has not yet been recorded.
        //
        // KNOWN LIMITATION, recorded deliberately and NOT fixed here: the send
        // is recorded against `now` — the day the notification was *scheduled* —
        // even when the quiet-hours branch held it until tomorrow morning. Ten
        // memos held after 22:00 therefore spend Monday's budget, are delivered
        // Tuesday at 08:00, and Tuesday's fresh budget allows ten more: twenty
        // banners in one morning, the outcome the cap exists to prevent. The
        // clean fix is to check and record against the DELIVERY day, but the cap
        // is checked inside NotificationPolicy.decide before a delivery date
        // exists, so the fix is circular and would reopen the core closed in
        // task 9. Reaching it needs ten uncategorizable payments between 22:00
        // and 08:00; dogfooding will show whether that happens in practice.
        CapturePrefs.recordNotification(now: now)
        if let stored = MemoStore.find(hash: captureHash, in: ctx) {
            stored.notifiedAt = now
            try? ctx.save()
        }
    }

    /// Action titles are baked in at registration, so a distinct set of choices
    /// needs a distinct category id. Registration is cheap and idempotent.
    ///
    /// KNOWN LIMITATION, recorded not fixed: `setNotificationCategories`
    /// *replaces* the registered set, so only the most recent choice-set stays
    /// registered. Two notifications pending at once with different choice-sets
    /// leave the older one's buttons stale. Accepted for the beta; the
    /// alternative is accumulating categories forever.
    ///
    /// The returned id is an OPAQUE KEY, not a data structure. Nothing may
    /// recover the choice list by splitting it — a user-created category can
    /// contain the separator.
    private static func register(choices: [String]) -> String {
        let id = ([categoryPrefix] + choices).joined(separator: "|")
        var actions = choices.map {
            UNNotificationAction(identifier: "\(categoryActionPrefix)\($0)",
                                 title: $0, options: [])
        }
        actions.append(UNNotificationAction(identifier: laterActionID,
                                            title: "Later", options: []))
        let category = UNNotificationCategory(identifier: id, actions: actions,
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        return id
    }

    /// The category an action id carries, or nil if it carries none.
    ///
    /// Strips the known prefix; never splits on "|". A user may name a category
    /// "Rent | Utilities", and splitting would silently assign "Rent ".
    static func category(fromActionID actionID: String) -> String? {
        guard actionID.hasPrefix(categoryActionPrefix) else { return nil }
        let category = String(actionID.dropFirst(categoryActionPrefix.count))
        return category.isEmpty ? nil : category
    }

    // MARK: - responding to a notification

    /// A category chosen from a notification button, waiting to be offered as a
    /// rule the next time the app is opened.
    ///
    /// Persisted rather than held in memory because a category button does not
    /// foreground the app: the process can be suspended and killed before the
    /// user ever opens Hisab. The assignment itself is already in the store, so
    /// only the offer would be lost — but the offer is the durable value this
    /// whole feature exists to produce.
    struct RuleOffer: Sendable, Equatable {
        var captureHash: String
        var category: String
    }

    private static let ruleOfferKey = "capture.pendingRuleOffer"

    /// Consumed by the review UI (task 11), which turns it into a
    /// `StoredCategoryRule` if the user accepts and clears it either way.
    /// Stored as a two-element array, not a joined string, so no reader is ever
    /// tempted to split a category name apart again.
    static var pendingRuleOffer: RuleOffer? {
        get {
            guard let parts = UserDefaults.standard.array(forKey: ruleOfferKey) as? [String],
                  parts.count == 2 else { return nil }
            return RuleOffer(captureHash: parts[0], category: parts[1])
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: ruleOfferKey)
                return
            }
            UserDefaults.standard.set([newValue.captureHash, newValue.category],
                                      forKey: ruleOfferKey)
        }
    }

    /// Applies one notification response: a category button assigns and queues
    /// the rule offer; anything else routes the user to the memo.
    static func respond(actionID: String, captureHash: String?,
                        router: DeepLinkRouter, in ctx: ModelContext) {
        guard let captureHash, !captureHash.isEmpty else {
            // A payload-less notification can still be tapped. Land the user
            // somewhere real rather than on whatever tab was last open.
            router.showNeedsReview = true
            return
        }
        guard let category = category(fromActionID: actionID) else {
            // MEMO_LATER and the default (body) tap both land here.
            router.pendingMemoHash = captureHash
            return
        }
        guard let memo = MemoStore.find(hash: captureHash, in: ctx) else {
            router.pendingMemoHash = captureHash
            return
        }
        MemoStore.assign(category: category, to: memo, in: ctx)
        pendingRuleOffer = RuleOffer(captureHash: captureHash, category: category)
    }
}
