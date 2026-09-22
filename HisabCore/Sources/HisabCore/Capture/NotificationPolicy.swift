import Foundation

public enum NotificationDecision: Equatable, Sendable {
    case send
    /// Held so Hisab never wakes anyone; deliver at this instant instead.
    case hold(until: Date)
    /// Today's budget is spent. The needs-review inbox still carries the memo,
    /// so nothing is lost — only the interruption is dropped.
    case suppress
}

/// When Hisab may interrupt the user about an uncategorized payment.
public enum NotificationPolicy {
    public static let dailyCap = 10
    public static let quietStartHour = 22
    public static let quietEndHour = 8

    public static func decide(now: Date, sentToday: Int) -> NotificationDecision {
        if sentToday >= dailyCap { return .suppress }
        let hour = YearMonth.istCalendar.component(.hour, from: now)
        guard hour >= quietStartHour || hour < quietEndHour else { return .send }

        // Before 08:00 the hold lands today; from 22:00 it lands tomorrow.
        let base = hour < quietEndHour
            ? now
            : YearMonth.istCalendar.date(byAdding: .day, value: 1, to: now) ?? now
        var components = YearMonth.istCalendar.dateComponents([.year, .month, .day], from: base)
        components.hour = quietEndHour
        components.minute = 0
        components.second = 0
        guard let until = YearMonth.istCalendar.date(from: components) else { return .send }
        return .hold(until: until)
    }
}
