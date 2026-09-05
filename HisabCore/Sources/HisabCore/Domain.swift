import Foundation

public enum SourceKind: String, Codable, Sendable {
    case paymentApp, bank
}

/// The four statement sources Hisab understands. Extend here to add a fifth.
public enum Source: String, Codable, CaseIterable, Sendable, Identifiable {
    case gpay, paytm, hdfc, idfc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gpay: "Google Pay"
        case .paytm: "Paytm"
        case .hdfc: "HDFC Bank"
        case .idfc: "IDFC First Bank"
        }
    }

    public var kind: SourceKind {
        switch self {
        case .gpay, .paytm: .paymentApp
        case .hdfc, .idfc: .bank
        }
    }
}

public enum Direction: String, Codable, Sendable {
    case debit, credit
}

/// An inclusive date range, month-resolved in IST.
public struct DatePeriod: Codable, Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var months: [YearMonth] {
        YearMonth.months(from: YearMonth(date: start), through: YearMonth(date: end))
    }
}

/// One transaction as read out of a statement file. Sign lives in `direction`; `amountPaise` is positive.
public struct ParsedTransaction: Sendable, Equatable {
    public let date: Date
    public let amountPaise: Int64
    public let direction: Direction
    public let counterparty: String
    public let reference: String?
    public let narration: String

    public init(date: Date, amountPaise: Int64, direction: Direction,
                counterparty: String, reference: String?, narration: String) {
        self.date = date
        self.amountPaise = amountPaise
        self.direction = direction
        self.counterparty = counterparty
        self.reference = reference
        self.narration = narration
    }
}
