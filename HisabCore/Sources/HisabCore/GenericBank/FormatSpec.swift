import Foundation

/// A bank-statement layout, described declaratively. Specs are trusted for
/// format *selection* only — their output must still close the balance chain
/// on the user's own file. Hard rule: this format never grows an expression
/// language or any eval-like field.
public struct FormatSpec: Codable, Equatable, Sendable {
    public var id: String                       // "sbi-table"
    public var sourceID: String                 // "bank:sbi" (or a frozen legacy id)
    public var bankName: String                 // "State Bank of India"
    public var provisional: Bool                // shape confirmed, quirks unverified
    /// role → case-insensitive regex matched against a header cell.
    /// Roles: date, narration, reference, debit, credit, amount, drcr, balance.
    public var headerPatterns: [String: String]
    /// Whole-row regexes (cells joined with "|") dropped from the body.
    public var furniturePatterns: [String]
    /// Tried in order; the first that parses every body date wins.
    public var dateFormats: [String]
    /// "debitCredit" | "signedAmount" | "amountDRCR" | "unsignedChain"
    public var signConvention: String
    /// Optional regexes (one capture group) extracting a rail reference from
    /// the narration when no reference cell is present. See ColumnMapping.
    public var referencePatterns: [String]?

    public init(id: String, sourceID: String, bankName: String, provisional: Bool = false,
                headerPatterns: [String: String], furniturePatterns: [String] = [],
                dateFormats: [String], signConvention: String,
                referencePatterns: [String]? = nil) {
        self.id = id
        self.sourceID = sourceID
        self.bankName = bankName
        self.provisional = provisional
        self.headerPatterns = headerPatterns
        self.furniturePatterns = furniturePatterns
        self.dateFormats = dateFormats
        self.signConvention = signConvention
        self.referencePatterns = referencePatterns
    }
}

public enum SpecStore {
    /// Decodes every Resources/formats/*.json in the package bundle.
    public static func bundled() -> [FormatSpec] {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "json",
                                            subdirectory: "Resources/formats") else { return [] }
        let decoder = JSONDecoder()
        var specs: [FormatSpec] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url),
               let spec = try? decoder.decode(FormatSpec.self, from: data) {
                specs.append(spec)
            }
        }
        return specs
    }
}
