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

    /// `fileHash` overrides the identity used for the file-level duplicate
    /// check. Real imports leave it nil and are identified by their bytes; the
    /// demo statements are rewritten to the current month before import, so
    /// their bytes differ every month and they pass the *bundle's* hash instead
    /// — otherwise loading the demo twice in different months would import it
    /// twice. See DemoData.
    func importFile(at url: URL, password: String?, overrideSource: Source?,
                    fileHash fileHashOverride: String? = nil) throws -> ImportReport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportServiceError.unreadable }

        let fileHash = fileHashOverride
            ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

        var inserted: [StoredTransaction] = []
        for index in newIndices {
            let txn = StoredTransaction(parsed: parsed.transactions[index],
                                        source: source, document: document)
            context.insert(txn)
            inserted.append(txn)
        }

        // After insertion and before the save, so a throw anywhere above leaves
        // every memo exactly where it was. A memo retired against a statement
        // that never landed would vanish from the inbox with nothing to show
        // for it.
        retireMemos(against: inserted)

        let months = parsed.effectivePeriod.months
        for month in months {
            Queries.recomputeMatches(context, month: month)
        }
        try context.save()

        // Housekeeping, deliberately AFTER the save rather than beside the
        // merge: `MemoStore.expire` saves the context itself, so calling it
        // above would commit the retirements before `try context.save()` had
        // a chance to throw — the one thing the placement of `retireMemos` is
        // there to prevent. Expiry is not part of this import's outcome; a
        // memo old enough to drop is old enough whatever the file contained.
        MemoStore.expire(now: Date(), in: context)

        return ImportReport(source: source, totalParsed: parsed.transactions.count,
                            newCount: newIndices.count, monthsTouched: months,
                            duplicateOfExistingFile: false)
    }

    /// Attaches memos to the statement rows they turn out to have been about.
    ///
    /// A memo is a note about a payment, never a ledger entry: an alert carries
    /// no UTR, so it can join neither content-hash dedup nor balance-chain
    /// validation. When the statement finally arrives, the payment enters the
    /// ledger as an ordinary row and the memo's job is done — `mergedTxnUUID`
    /// is what takes it out of the needs-review inbox (see `MemoStore.pending`)
    /// without deleting the user's own note and category.
    ///
    /// Only the rows this import actually inserted are offered as candidates.
    /// Rows already in the store were offered to these same memos by the import
    /// that brought them in, and re-offering them would let a second import of
    /// an unrelated month re-open a decision that was already made against a
    /// larger, more complete candidate set.
    ///
    /// `MemoMerger` owns every rule about what may pair with what, and is
    /// pinned to its Dart twin by shared fixtures. Nothing here may second-guess
    /// it: this function projects rows in, and writes the result back out.
    private func retireMemos(against inserted: [StoredTransaction]) {
        guard !inserted.isEmpty else { return }
        let open = MemoStore.all(context).filter { $0.mergedTxnUUID == nil }
        guard !open.isEmpty else { return }

        // `"\(counterparty) \(narration)"` is the exact text
        // `Queries.category(of:rules:)` categorizes on, so the VPA and payee
        // gates see the same string the rule matcher does. A narrower
        // projection would make a memo fail to merge onto a row a rule written
        // from that very memo would happily claim.
        let candidates = inserted.map {
            MemoMergeCandidate(id: $0.uuid, date: $0.date, amountPaise: $0.amountPaise,
                               direction: $0.direction,
                               narration: "\($0.counterparty) \($0.narration)")
        }
        let paired = MemoMerger.merge(memos: open.map(\.asMemo), candidates: candidates)
        guard !paired.isEmpty else { return }

        for memo in open {
            // `asMemo.captureHash` recomputes from the same stored fields the
            // hash was built from at capture, so the stored column is the key
            // `merge` returned. Reading the column keeps this a lookup rather
            // than a second hashing of every memo.
            guard let txnUUID = paired[memo.captureHash] else { continue }
            memo.mergedTxnUUID = txnUUID
        }
    }

    /// Keeps the original bytes so a future parser fix can re-run over past uploads.
    private func copyIntoSandbox(data: Data, hash: String, filename: String) {
        let dir = URL.documentsDirectory.appending(path: "imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(hash)-\(filename)"))
    }
}
