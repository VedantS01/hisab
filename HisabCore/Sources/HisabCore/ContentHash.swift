import Foundation
import CryptoKit

extension ParsedTransaction {
    /// Stable identity used for cross-document dedup. Within a source, a transaction
    /// reference ID (UPI/bank ref) IS the identity — the same ID can never insert
    /// twice, whatever document (monthly, yearly, PDF, XLSX) it arrives in. Rows
    /// without a reference fall back to day + amount + direction + normalized
    /// narration. App-side and bank-side copies of one payment intentionally hash
    /// differently (different source): linking those is reconciliation's job.
    public func contentHash(source: Source) -> String {
        let canonical: String
        if let reference, !reference.isEmpty {
            // Direction stays in the key: a refund/cancellation reuses its original
            // payment's reference with the opposite direction and is a distinct movement.
            canonical = "\(source.rawValue)|ref|\(reference)|\(direction.rawValue)"
        } else {
            let formatter = DateFormatter()
            formatter.calendar = YearMonth.istCalendar
            formatter.timeZone = YearMonth.istCalendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let day = formatter.string(from: date)
            canonical = "\(source.rawValue)|\(day)|\(amountPaise)|\(direction.rawValue)|\(Self.normalized(narration))"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
