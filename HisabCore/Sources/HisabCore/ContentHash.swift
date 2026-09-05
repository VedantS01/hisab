import Foundation
import CryptoKit

extension ParsedTransaction {
    /// Stable identity used for cross-document dedup. Reference-keyed when the format
    /// carries one; otherwise falls back to whitespace/case-normalized narration.
    public func contentHash(source: Source) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        let key = reference ?? Self.normalized(narration)
        let canonical = "\(source.rawValue)|\(day)|\(amountPaise)|\(direction.rawValue)|\(key)"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
