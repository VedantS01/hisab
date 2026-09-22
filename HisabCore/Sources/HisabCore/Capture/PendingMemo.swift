import Foundation
import CryptoKit

/// A transaction alert Hisab captured but has NOT admitted to the ledger.
///
/// Alerts carry no UTR, so they cannot join content-hash dedup or
/// balance-chain validation — the two properties that make Hisab's numbers
/// trustworthy. A memo's durable output is a categorization *rule*; the
/// statement remains the single source of truth. See the design spec.
public struct PendingMemo: Sendable, Equatable, Codable {
    public var amountPaise: Int64
    public var direction: Direction
    /// As it appeared in the alert, for display.
    public var payee: String
    /// VPA in full (`name@handle`), lowercased, when the alert carried one.
    public var vpa: String?
    /// Trailing digits of the account the alert named, e.g. "1234".
    public var accountTail: String?
    /// The transaction's own date (the alert's, or capture time if absent).
    public var date: Date
    public var capturedAt: Date
    public var note: String?

    public init(amountPaise: Int64, direction: Direction, payee: String,
                vpa: String?, accountTail: String?, date: Date,
                capturedAt: Date, note: String? = nil) {
        self.amountPaise = amountPaise
        self.direction = direction
        self.payee = payee
        self.vpa = vpa?.lowercased()
        self.accountTail = accountTail
        self.date = date
        self.capturedAt = capturedAt
        self.note = note
    }

    /// Cluster key shared with the suggestion engine so a rule written here
    /// matches patterns the rule store already contains.
    public var payeeNormalized: String { SuggestionEngine.normalize(payee) }

    /// `yyyy-MM-dd` in IST. Day granularity is deliberate: Android fires on
    /// notification *updates*, and a timestamp would defeat the dedup guard.
    public static func istDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Stable identity. Two captures of one payment collapse; a refund of the
    /// same amount to the same payee stays distinct (direction is in the key).
    public var captureHash: String {
        let canonical = [
            String(amountPaise),
            direction.rawValue,
            payeeNormalized,
            vpa ?? "",
            Self.istDayString(date),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var ruleKey: RuleKey {
        if let vpa, vpa.count >= 3 { return RuleKey(pattern: vpa, kind: .vpa) }
        return RuleKey(pattern: payeeNormalized, kind: .merchant)
    }
}

public extension PendingMemo {
    /// Memos are a labelling channel, not storage. Statements arrive monthly;
    /// 45 days leaves buffer for a late import without unbounded growth.
    static let expiryDays = 45

    static func isExpired(capturedAt: Date, now: Date) -> Bool {
        let days = YearMonth.istCalendar.dateComponents([.day], from: capturedAt, to: now).day ?? 0
        return days > expiryDays
    }
}

public enum RuleKeyKind: String, Codable, Sendable {
    case vpa, merchant
}

/// What a rule written from a memo should match on. The VPA is preferred
/// because personal-name payees render inconsistently across statements
/// ("VEDANT SABOO", "Vedant S", "UPI/1234/VEDANT") while `name@handle` does
/// not — and UPI narrations carry the VPA verbatim, so the longest-match
/// matcher will pick it.
public struct RuleKey: Equatable, Sendable, Codable {
    public var pattern: String
    public var kind: RuleKeyKind

    public init(pattern: String, kind: RuleKeyKind) {
        self.pattern = pattern
        self.kind = kind
    }
}
