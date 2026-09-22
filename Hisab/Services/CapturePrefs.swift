import Foundation
import HisabCore

/// Capture is a property of this device, not of the user's ledger.
enum CapturePrefs {
    private static let enabledKey = "capture.enabled"
    private static let lastCaptureKey = "capture.lastCaptureAt"
    private static let notifyCountKey = "capture.notifyCount"
    private static let notifyDayKey = "capture.notifyDay"

    /// Off by default. The user opts in.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastCaptureAt: Date? {
        get { UserDefaults.standard.object(forKey: lastCaptureKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastCaptureKey) }
    }

    /// Notifications sent today, so a heavy UPI day cannot spam. Resets when
    /// the IST day changes.
    static func notificationsSentToday(now: Date) -> Int {
        let today = PendingMemo.istDayString(now)
        guard UserDefaults.standard.string(forKey: notifyDayKey) == today else { return 0 }
        return UserDefaults.standard.integer(forKey: notifyCountKey)
    }

    static func recordNotification(now: Date) {
        let today = PendingMemo.istDayString(now)
        let count = notificationsSentToday(now: now) + 1
        UserDefaults.standard.set(today, forKey: notifyDayKey)
        UserDefaults.standard.set(count, forKey: notifyCountKey)
    }
}
