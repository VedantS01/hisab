import Foundation

/// Deterministic identity for bank rows without a rail reference. Keyed on the
/// running balance so the same movement hashes identically across renditions
/// (PDF vs XLSX vs generic-engine parses) whose narrations differ. The shape
/// never collides with real UPI/NEFT references.
public enum SyntheticRef {
    public static func make(balancePaise: Int64, date: Date, amountPaise: Int64) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return "B\(balancePaise)D\(formatter.string(from: date))A\(amountPaise)"
    }
}
