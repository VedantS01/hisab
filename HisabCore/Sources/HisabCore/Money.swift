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

    /// "-453.00" -> -45300; "+600" -> 60000; commas tolerated. Nil when not a decimal amount.
    public static func signedPaise(fromDecimalString raw: String) -> Int64? {
        var text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        var sign: Int64 = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() }
        else if text.hasPrefix("+") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, !parts[0].isEmpty, let rupees = Int64(parts[0]), rupees >= 0 else { return nil }
        var fraction: Int64 = 0
        if parts.count == 2 {
            let digits = parts[1]
            guard (1...2).contains(digits.count), let value = Int64(digits) else { return nil }
            fraction = digits.count == 1 ? value * 10 : value
        }
        return sign * (rupees * 100 + fraction)
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
