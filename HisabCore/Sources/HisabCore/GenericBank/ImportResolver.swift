import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

public enum Resolution: Sendable {
    case parsed(ParsedDocument)
    case passwordRequired
    /// No engine could read the file at all.
    case unsupported(FormatFingerprint)
    /// A table was read but no interpretation closed the balance chain —
    /// corrupt, truncated, or a layout quirk we don't know yet.
    case unverified(FormatFingerprint, detail: String)
}

/// The one import entry point: curated code parsers, then bundled specs, then
/// conservative inference — and never a partial or best-guess import.
public struct ImportResolver: Sendable {
    public let registry: ParserRegistry
    public let specs: [FormatSpec]

    public init(registry: ParserRegistry, specs: [FormatSpec]) {
        self.registry = registry
        self.specs = specs
    }

    public static func live() -> ImportResolver {
        ImportResolver(registry: .live, specs: SpecStore.bundled())
    }

    public func resolve(data: Data, filename: String, password: String?) -> Resolution {
        // 1. Curated code parsers keep first claim; their errors fall through to
        //    the generic path rather than blocking it.
        if let parser = registry.detect(data: data, filename: filename) {
            do {
                return .parsed(try parser.parse(data: data, password: password))
            } catch ParseError.passwordRequired {
                return .passwordRequired
            } catch {
                // fall through
            }
        }

        #if canImport(PDFKit)
        if filename.lowercased().hasSuffix(".pdf"), let doc = PDFDocument(data: data),
           doc.isLocked, password == nil {
            return .passwordRequired
        }
        #endif

        // 2. A table, or nothing.
        guard let table = NormalizedTable.from(data: data, filename: filename,
                                               password: password) else {
            let ext = (filename as NSString).pathExtension.lowercased()
            let empty = NormalizedTable(rows: [], container: ext.isEmpty ? "unknown" : ext)
            return .unsupported(FormatFingerprint.make(table: empty))
        }

        // 3. Bundled specs, in bundle order.
        var brokenDetail: String?
        for spec in specs {
            switch SpecExecutor.execute(table: table, spec: spec) {
            case .validated(let txns)?:
                let doc = ParsedDocument(source: Source(rawValue: spec.sourceID),
                                         declaredPeriod: nil, transactions: txns)
                return .parsed(doc)
            case .broken(let row, let detail)?:
                if brokenDetail == nil { brokenDetail = "\(spec.id) row \(row): \(detail)" }
            case nil:
                continue
            }
        }

        // 4. Conservative inference.
        let fingerprint = FormatFingerprint.make(table: table)
        if let result = ColumnInference.infer(table: table) {
            let slug = fingerprint.bankNameGuess.map(Self.slugify) ?? "other"
            let doc = ParsedDocument(source: Source(rawValue: "bank:\(slug)"),
                                     declaredPeriod: nil, transactions: result.transactions)
            return .parsed(doc)
        }

        // 5. Refuse honestly.
        if let brokenDetail {
            return .unverified(fingerprint, detail: brokenDetail)
        }
        return .unsupported(fingerprint)
    }

    /// "Bank of Baroda" → "bankofbaroda". Deterministic so re-imports dedup.
    static func slugify(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter {
            ("a"..."z").contains(String($0)) || ("0"..."9").contains(String($0))
        }.map(Character.init))
    }
}
