import Foundation
import SwiftData
import HisabCore

@Model
final class StoredDocument {
    var uuid: UUID = UUID()
    var sourceRaw: String = ""
    var filename: String = ""
    var fileSHA256: String = ""
    var periodStart: Date = Date.distantPast
    var periodEnd: Date = Date.distantPast
    var importedAt: Date = Date.distantPast
    @Relationship(deleteRule: .cascade, inverse: \StoredTransaction.document)
    var transactions: [StoredTransaction]? = []

    init(source: Source, filename: String, fileSHA256: String, period: DatePeriod) {
        self.uuid = UUID()
        self.sourceRaw = source.rawValue
        self.filename = filename
        self.fileSHA256 = fileSHA256
        self.periodStart = period.start
        self.periodEnd = period.end
        self.importedAt = Date()
    }

    var source: Source { Source(rawValue: sourceRaw) ?? .gpay }
    var period: DatePeriod { DatePeriod(start: periodStart, end: periodEnd) }
}

@Model
final class StoredTransaction {
    var uuid: UUID = UUID()
    @Attribute(.unique) var contentHash: String = ""
    var date: Date = Date.distantPast
    var amountPaise: Int64 = 0
    var directionRaw: String = ""
    var counterparty: String = ""
    var reference: String?
    var narration: String = ""
    var sourceRaw: String = ""
    var categoryOverride: String?
    var document: StoredDocument?

    init(parsed: ParsedTransaction, source: Source, document: StoredDocument) {
        self.uuid = UUID()
        self.contentHash = parsed.contentHash(source: source)
        self.date = parsed.date
        self.amountPaise = parsed.amountPaise
        self.directionRaw = parsed.direction.rawValue
        self.counterparty = parsed.counterparty
        self.reference = parsed.reference
        self.narration = parsed.narration
        self.sourceRaw = source.rawValue
        self.document = document
    }

    var direction: Direction { Direction(rawValue: directionRaw) ?? .debit }
    var source: Source { Source(rawValue: sourceRaw) ?? .gpay }
    var month: YearMonth { YearMonth(date: date) }
}

@Model
final class StoredCategoryRule {
    var uuid: UUID = UUID()
    var pattern: String = ""
    var category: String = ""
    var sortOrder: Int = 0

    init(pattern: String, category: String, sortOrder: Int) {
        self.uuid = UUID()
        self.pattern = pattern
        self.category = category
        self.sortOrder = sortOrder
    }

    var asRule: CategoryRule { CategoryRule(id: uuid, pattern: pattern, category: category) }
}

@Model
final class StoredMatch {
    var appUUID: UUID = UUID()
    var bankUUID: UUID = UUID()
    var tierRaw: String = ""
    var monthKey: String = ""   // YearMonth.description, e.g. "2026-09"

    init(appUUID: UUID, bankUUID: UUID, tier: MatchTier, month: YearMonth) {
        self.appUUID = appUUID
        self.bankUUID = bankUUID
        self.tierRaw = tier.rawValue
        self.monthKey = month.description
    }

    var tier: MatchTier { MatchTier(rawValue: tierRaw) ?? .amountDate }
}

@Model
final class PinnedMonth {
    var year: Int = 0
    var month: Int = 0

    init(_ ym: YearMonth) {
        self.year = ym.year
        self.month = ym.month
    }

    var yearMonth: YearMonth { YearMonth(year: year, month: month) }
}
