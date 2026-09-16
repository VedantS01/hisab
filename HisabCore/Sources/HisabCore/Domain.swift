import Foundation

public enum SourceKind: String, Codable, Sendable {
    case paymentApp, bank
}

/// Statement sources. The five original ids are frozen (they live inside stored
/// content hashes); new banks and apps use open ids like "bank:sbi" or "upi:phonepe".
public struct Source: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public static let gpay = Source(rawValue: "gpay")
    public static let paytm = Source(rawValue: "paytm")
    public static let bhim = Source(rawValue: "bhim")
    public static let hdfc = Source(rawValue: "hdfc")
    public static let idfc = Source(rawValue: "idfc")
    /// Sources with first-party parsers; drives pickers, filters, and capability copy.
    public static let builtIn: [Source] = [.gpay, .paytm, .bhim, .hdfc, .idfc]

    public var kind: SourceKind {
        switch rawValue {
        case "gpay", "paytm", "bhim": return .paymentApp
        default: return rawValue.hasPrefix("upi:") ? .paymentApp : .bank
        }
    }

    public var displayName: String {
        switch rawValue {
        case "gpay": return "Google Pay"
        case "paytm": return "Paytm"
        case "bhim": return "BHIM UPI"
        case "hdfc": return "HDFC Bank"
        case "idfc": return "IDFC First Bank"
        default:
            let slug = rawValue.split(separator: ":").last.map(String.init) ?? rawValue
            return slug.count <= 4 ? slug.uppercased() : slug.capitalized
        }
    }

    /// Payment apps first, then banks, alphabetical by display name within kind.
    public static func ordered(_ sources: some Sequence<Source>) -> [Source] {
        Set(sources).sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .paymentApp }
            return lhs.displayName < rhs.displayName
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
