import Foundation

public struct ParsedDocument: Sendable {
    public let source: Source
    public let declaredPeriod: DatePeriod?
    public let transactions: [ParsedTransaction]

    public init(source: Source, declaredPeriod: DatePeriod?, transactions: [ParsedTransaction]) {
        self.source = source
        self.declaredPeriod = declaredPeriod
        self.transactions = transactions
    }

    /// Declared statement period when the format carries one, else the span of its rows.
    public var effectivePeriod: DatePeriod {
        if let declaredPeriod { return declaredPeriod }
        let dates = transactions.map(\.date)
        precondition(!dates.isEmpty, "document with no period and no transactions")
        return DatePeriod(start: dates.min()!, end: dates.max()!)
    }
}

public enum ParseError: Error, Equatable {
    case unrecognizedFormat
    case passwordRequired
    case malformedRow(Int, String)   // 1-based file line number, raw line
    case empty
}

public protocol StatementParser: Sendable {
    var source: Source { get }
    func canParse(data: Data, filename: String) -> Bool
    func parse(data: Data, password: String?) throws -> ParsedDocument
}

public struct ParserRegistry: Sendable {
    private let parsers: [any StatementParser]

    public init(parsers: [any StatementParser]) {
        self.parsers = parsers
    }

    public func detect(data: Data, filename: String) -> (any StatementParser)? {
        parsers.first { $0.canParse(data: data, filename: filename) }
    }

    /// Real HDFC/IDFC parsers are appended here as they land.
    public static var live: ParserRegistry {
        var parsers: [any StatementParser] = [SyntheticCSVParser(), PaytmXLSXParser()]
        #if canImport(PDFKit)
        parsers.append(GPayPDFParser())
        #endif
        return ParserRegistry(parsers: parsers)
    }
}
