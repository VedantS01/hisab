import Foundation
import CryptoKit
import SwiftData
import HisabCore

struct ImportReport {
    let source: Source
    let totalParsed: Int
    let newCount: Int
    let monthsTouched: [YearMonth]
    let duplicateOfExistingFile: Bool
}

enum ImportServiceError: Error, LocalizedError {
    case unreadable
    case unsupportedFormat(FormatFingerprint)
    case unverifiedStatement(FormatFingerprint, String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "Could not read the selected file."
        case .unsupportedFormat: "Hisab can't read this statement format yet."
        case .unverifiedStatement: "Couldn't verify this statement — its running balance doesn't add up."
        }
    }
}

@MainActor
final class ImportService {
    private let context: ModelContext
    private let resolver: ImportResolver

    init(context: ModelContext, resolver: ImportResolver = .live()) {
        self.context = context
        self.resolver = resolver
    }

    func importFile(at url: URL, password: String?, overrideSource: Source?) throws -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportServiceError.unreadable }

        let fileHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let existingDocs = (try? context.fetch(FetchDescriptor<StoredDocument>())) ?? []
        if let dup = existingDocs.first(where: { $0.fileSHA256 == fileHash }) {
            return ImportReport(source: dup.source, totalParsed: 0, newCount: 0,
                                monthsTouched: [], duplicateOfExistingFile: true)
        }

        let parsed: ParsedDocument
        switch resolver.resolve(data: data, filename: url.lastPathComponent, password: password) {
        case .parsed(let doc):
            parsed = doc
        case .passwordRequired:
            throw ParseError.passwordRequired
        case .unsupported(let fingerprint):
            throw ImportServiceError.unsupportedFormat(fingerprint)
        case .unverified(let fingerprint, let detail):
            throw ImportServiceError.unverifiedStatement(fingerprint, detail)
        }
        let source = overrideSource ?? parsed.source

        let existingHashes = Set(
            ((try? context.fetch(FetchDescriptor<StoredTransaction>())) ?? [])
                .filter { $0.sourceRaw == source.rawValue }
                .map(\.contentHash))
        let newIndices = Dedup.newIndices(incoming: parsed.transactions, source: source,
                                          existingHashes: existingHashes)

        let document = StoredDocument(source: source, filename: url.lastPathComponent,
                                      fileSHA256: fileHash, period: parsed.effectivePeriod)
        context.insert(document)
        copyIntoSandbox(data: data, hash: fileHash, filename: url.lastPathComponent)

        for index in newIndices {
            context.insert(StoredTransaction(parsed: parsed.transactions[index],
                                             source: source, document: document))
        }

        let months = parsed.effectivePeriod.months
        for month in months {
            Queries.recomputeMatches(context, month: month)
        }
        try context.save()

        return ImportReport(source: source, totalParsed: parsed.transactions.count,
                            newCount: newIndices.count, monthsTouched: months,
                            duplicateOfExistingFile: false)
    }

    /// Keeps the original bytes so a future parser fix can re-run over past uploads.
    private func copyIntoSandbox(data: Data, hash: String, filename: String) {
        let dir = URL.documentsDirectory.appending(path: "imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(hash)-\(filename)"))
    }
}
