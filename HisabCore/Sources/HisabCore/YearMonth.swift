import Foundation

/// A calendar month, resolved in Indian Standard Time.
public struct YearMonth: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int  // 1...12

    public static var istCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month out of range: \(month)")
        self.year = year
        self.month = month
    }

    public init(date: Date) {
        let comps = Self.istCalendar.dateComponents([.year, .month], from: date)
        self.init(year: comps.year!, month: comps.month!)
    }

    public func advanced(by months: Int) -> YearMonth {
        let total = year * 12 + (month - 1) + months
        let y = total >= 0 ? total / 12 : (total - 11) / 12
        return YearMonth(year: y, month: total - y * 12 + 1)
    }

    public static func months(from: YearMonth, through: YearMonth) -> [YearMonth] {
        guard from <= through else { return [] }
        var result: [YearMonth] = []
        var current = from
        while current <= through {
            result.append(current)
            current = current.advanced(by: 1)
        }
        return result
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    public var description: String {
        String(format: "%04d-%02d", year, month)
    }

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    public var displayName: String {
        "\(Self.monthNames[month - 1]) \(year)"
    }
}
