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

    /// Takes a copy of a document handed to Hisab from the share sheet, Files
    /// or Mail, and returns the copy to import.
    ///
    /// The URL `onOpenURL` delivers is security-scoped and open IN PLACE: it
    /// is readable inside `startAccessingSecurityScopedResource()` and for as
    /// long as the system chooses to keep the grant alive, which is not long
    /// enough. Presenting a sheet is at least one run-loop turn away, the user
    /// may then sit on a password prompt for a minute, and a `Data(contentsOf:)`
    /// at the far end of that fails with a permission error that looks exactly
    /// like an unreadable file. Copying here, while the grant is certainly
    /// live, is what makes the rest of the flow ordinary file reading.
    ///
    /// The copy goes to `tmp`, not `Documents`: `copyIntoSandbox` already
    /// keeps the durable copy under `Documents/imports`, and a second one in a
    /// directory `UIFileSharingEnabled` now exposes would be both redundant
    /// and a statement sitting somewhere the user did not put it.
    ///
    /// Returns the ORIGINAL url when the copy fails, rather than nil. Every
    /// failure this can hit is one `importFile` can hit too, and it reports
    /// them through the sheet's error UI; returning nil would mean deciding
    /// here to show the user nothing at all.
    nonisolated static func stageIncomingFile(at url: URL) -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appending(path: "incoming")
        // The staged copy keeps the sender's filename, extension included.
        // That is not cosmetic: `ImportResolver` gates its locked-PDF check on
        // `filename.hasSuffix(".pdf")`, so a copy renamed to something neutral
        // would turn a password-protected statement into "Hisab can't read
        // this format yet" — a dead end instead of a password prompt.
        let destination = directory.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            // The same statement can be sent twice; the second send must not
            // fail on "file exists" and silently import the first one's bytes.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }

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
        let supersededMonths = source.kind == .paymentApp && source != .alert
            ? retireAlertRows(supersededBy: inserted) : []

        let months = parsed.effectivePeriod.months
        for month in Set(months).union(supersededMonths).sorted() {
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
    /// A memo is a note about a payment, never a ledger entry. (An alert that
    /// carries a payment-rail reference also gets a ledger row of its own, via
    /// `CaptureService`; the memo stays the labelling channel either way.) When
    /// the statement finally arrives, the payment's statement row is in the
    /// ledger and the memo's job is done — `mergedTxnUUID`
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

    /// Deletes captured-alert rows for payments this app export just brought
    /// in, returning the months they sat in so their matches are recomputed.
    ///
    /// Same reference and direction is the same payment (see `ContentHash`).
    /// The export is the fuller record, and both rows are app-side: only one
    /// can reconcile against the bank row, so keeping the alert's copy would
    /// count the payment twice. `CaptureService` applies the same rule when
    /// the alert arrives second.
    private func retireAlertRows(supersededBy inserted: [StoredTransaction]) -> Set<YearMonth> {
        let keys = Set(inserted.compactMap { txn in txn.reference.map { "\($0)|\(txn.directionRaw)" } })
        guard !keys.isEmpty else { return [] }
        let alertRaw = Source.alert.rawValue
        let alertRows = (try? context.fetch(FetchDescriptor<StoredTransaction>(
            predicate: #Predicate { $0.sourceRaw == alertRaw }))) ?? []
        var months: Set<YearMonth> = []
        for row in alertRows {
            guard let reference = row.reference, keys.contains("\(reference)|\(row.directionRaw)") else { continue }
            months.insert(row.month)
            context.delete(row)
        }
        return months
    }

    /// Keeps the original bytes so a future parser fix can re-run over past uploads.
    private func copyIntoSandbox(data: Data, hash: String, filename: String) {
        let dir = URL.documentsDirectory.appending(path: "imports")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appending(path: "\(hash)-\(filename)"))
    }
}
