import Foundation

/// Currency formatting. All amounts are integer paise; display uses Indian digit grouping.
public enum Money {
    /// 1234567890 paise -> "₹1,23,45,678.90". Negatives render "-₹…"; `signed` forces "+" on positives.
    public static func formatPaise(_ paise: Int64, signed: Bool = false) -> String {
        let negative = paise < 0
        let magnitude = paise.magnitude
        let rupees = magnitude / 100
        let fraction = magnitude % 100
        let grouped = indianGrouped(String(rupees))
        let prefix = negative ? "-" : (signed ? "+" : "")
        return "\(prefix)₹\(grouped).\(String(format: "%02d", fraction))"
    }

    /// Indian grouping: last three digits, then groups of two. "12345678" -> "1,23,45,678".
    private static func indianGrouped(_ digits: String) -> String {
        guard digits.count > 3 else { return digits }
        let split = digits.index(digits.endIndex, offsetBy: -3)
        let head = String(digits[..<split])
        let tail = String(digits[split...])
        var groups: [String] = []
        var remaining = Substring(head)
        while remaining.count > 2 {
            let cut = remaining.index(remaining.endIndex, offsetBy: -2)
            groups.insert(String(remaining[cut...]), at: 0)
            remaining = remaining[..<cut]
        }
        if !remaining.isEmpty { groups.insert(String(remaining), at: 0) }
        return (groups + [tail]).joined(separator: ",")
    }
}
