import Foundation
import SwiftData
import UserNotifications
import HisabCore

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
    static func considerNotifying(memo: PendingMemo, in ctx: ModelContext) {
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
        UNUserNotificationCenter.current().add(request)
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

        if let stored = MemoStore.find(hash: memo.captureHash, in: ctx) {
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
