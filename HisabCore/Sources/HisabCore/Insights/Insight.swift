import Foundation
import CryptoKit

/// "yyyy-MM-dd" and day arithmetic in IST — the same day key the content
/// hashes use, hoisted so the detectors don't each build a DateFormatter.
public enum ISTDay {
    public static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// "28 Aug 2026" — the one day rendering both apps use, so a date in a
    /// card's sentence and the same date in its evidence list read alike.
    public static func label(_ date: Date) -> String {
        let day = YearMonth.istCalendar.dateComponents([.day], from: date).day ?? 1
        return "\(day) \(YearMonth(date: date).displayName)"
    }

    /// Whole IST calendar days from `from` to `to`; negative when `to` is earlier.
    public static func daysBetween(_ from: Date, _ to: Date) -> Int {
        let cal = YearMonth.istCalendar
        let start = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

public enum InsightKind: String, Sendable, Codable, CaseIterable {
    case trend
    case recurringNew
    case recurringChanged
    case committedSpend
    case possibleDuplicate
    case outlierAmount
}

public enum Cadence: String, Sendable, Codable, Equatable {
    case monthly
    case weekly
}

/// What a card's overflow "don't show this" action suppresses.
public enum MuteTarget: Sendable, Equatable {
    case merchant(String)   // normalized merchant key
    case category(String)
}

public struct RecurringSeries: Sendable, Equatable {
    public let merchantKey: String
    public let displayMerchant: String
    public let cadence: Cadence
    public let medianPaise: Int64
    /// Weekly series are scaled by 52/12 so one number sums across cadences.
    public let monthlyEquivalentPaise: Int64
    public let firstSeen: Date
    public let lastSeen: Date
    public let count: Int
    public let transactionIDs: [String]

    public init(merchantKey: String, displayMerchant: String, cadence: Cadence,
                medianPaise: Int64, monthlyEquivalentPaise: Int64,
                firstSeen: Date, lastSeen: Date, count: Int, transactionIDs: [String]) {
        self.merchantKey = merchantKey
        self.displayMerchant = displayMerchant
        self.cadence = cadence
        self.medianPaise = medianPaise
        self.monthlyEquivalentPaise = monthlyEquivalentPaise
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = count
        self.transactionIDs = transactionIDs
    }
}

/// One card. Copy is generated in core so both platforms render the same
/// sentence and the parity fixture can assert it.
public struct Insight: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: InsightKind
    public let headline: String
    public let detail: String
    /// Transaction ids the card is evidence for; the evidence sheet lists them.
    public let evidenceIDs: [String]
    /// Populated for `.committedSpend` only.
    public let series: [RecurringSeries]
    public let score: Int64
    public let mute: MuteTarget?

    public init(id: String, kind: InsightKind, headline: String, detail: String,
                evidenceIDs: [String], series: [RecurringSeries] = [],
                score: Int64, mute: MuteTarget?) {
        self.id = id
        self.kind = kind
        self.headline = headline
        self.detail = detail
        self.evidenceIDs = evidenceIDs
        self.series = series
        self.score = score
        self.mute = mute
    }
}

/// One transaction as the insight engine sees it: the analytics projection
/// (deduped, self transfers excluded, matched bank rows excluded) plus the
/// row id so cards can point back at their evidence.
public struct InsightRecord: Sendable, Equatable {
    public let id: String
    public let date: Date
    public let amountPaise: Int64
    public let direction: Direction
    public let category: String
    public let merchant: String

    public init(id: String, date: Date, amountPaise: Int64, direction: Direction,
                category: String, merchant: String) {
        self.id = id
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.category = category
        self.merchant = merchant
    }
}

public struct InsightsInput: Sendable {
    public let records: [InsightRecord]
    /// Statement periods, used to decide which months are complete.
    public let documentPeriods: [DatePeriod]
    public let now: Date

    public init(records: [InsightRecord], documentPeriods: [DatePeriod], now: Date) {
        self.records = records
        self.documentPeriods = documentPeriods
        self.now = now
    }
}

public struct Suppressions: Sendable, Equatable {
    public var dismissedIDs: Set<String>
    public var mutedMerchants: Set<String>
    public var mutedCategories: Set<String>

    public init(dismissedIDs: Set<String> = [], mutedMerchants: Set<String> = [],
                mutedCategories: Set<String> = []) {
        self.dismissedIDs = dismissedIDs
        self.mutedMerchants = mutedMerchants
        self.mutedCategories = mutedCategories
    }
}

public struct InsightsResult: Sendable {
    /// Ranked, capped, suppression-applied — exactly what the strip shows.
    public let cards: [Insight]
    /// Every id generated this pass before suppression; the app prunes its
    /// dismissed set to this so stored ids can't grow without bound.
    public let allIDs: Set<String>

    public init(cards: [Insight], allIDs: Set<String>) {
        self.cards = cards
        self.allIDs = allIDs
    }
}

public enum InsightID {
    /// First 16 hex characters of SHA256 over the canonical string. Content
    /// derived, so a dismissed insight stays dismissed across recomputes but
    /// materially new numbers produce a new id.
    public static func make(_ canonical: String) -> String {
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }
}
