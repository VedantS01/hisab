import Foundation
import HisabCore

/// Capture is a property of this device, not of the user's ledger.
enum CapturePrefs {
    private static let enabledKey = "capture.enabled"
    private static let lastCaptureKey = "capture.lastCaptureAt"
    private static let lastAttemptKey = "capture.lastAttemptAt"
    private static let notifyCountKey = "capture.notifyCount"
    private static let notifyDayKey = "capture.notifyDay"

    /// Off by default. The user opts in.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The last time an alert was PARSED successfully.
    static var lastCaptureAt: Date? {
        get { UserDefaults.standard.object(forKey: lastCaptureKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCaptureKey) }
    }

    /// The last time an alert ARRIVED, whatever became of it — including one
    /// that arrived while capture was switched off, and one the parser could
    /// make nothing of.
    ///
    /// Health needs both timestamps because one cannot tell "the automation
    /// never fired" from "the automation fires but every parse fails", and
    /// those need opposite remediations: re-check your Shortcuts automation,
    /// versus nothing you can do, wait for an update. A warning that
    /// confidently sends the user to fix a working automation is worse than no
    /// warning.
    static var lastAttemptAt: Date? {
        get { UserDefaults.standard.object(forKey: lastAttemptKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastAttemptKey) }
    }

    /// Notifications sent today, so a heavy UPI day cannot spam. Resets when
    /// the IST day changes.
    static func notificationsSentToday(now: Date) -> Int {
        let today = PendingMemo.istDayString(now)
        guard UserDefaults.standard.string(forKey: notifyDayKey) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: notifyCountKey)
    }

    /// Not atomic: the read, increment and write are three steps, so two truly
    /// concurrent callers could lose an increment. Safe today because every
    /// caller is @MainActor and the process has one container. Anyone adding a
    /// non-main-actor caller must revisit this. Failure mode is under-counting
    /// toward the daily cap, never over-counting, so it cannot cause spam.
    static func recordNotification(now: Date) {
        let today = PendingMemo.istDayString(now)
        let count = notificationsSentToday(now: now) + 1
        UserDefaults.standard.set(today, forKey: notifyDayKey)
        UserDefaults.standard.set(count, forKey: notifyCountKey)
    }
}
