import Foundation
import SwiftData
import HisabCore

/// Files one transaction alert: a memo for labelling and, when the alert
/// carries a payment-rail reference, a ledger row. `AlertCapture` decides what
/// an alert yields; this writes it. The alert text itself is never stored or
/// logged — only what was read out of it.
@MainActor
enum CaptureService {
    /// What one alert did to the store. A side is nil when the alert yielded
    /// nothing for it: no payee to label (memo), no reference (row).
    struct Outcome {
        var memo: (memo: PendingMemo, result: MemoStore.InsertOutcome)?
        var row: (row: ParsedTransaction, result: MemoStore.InsertOutcome)?
    }

    /// The on-device extractor, loaded on first use and kept for the life of
    /// the process: loading costs far more than an extraction does. Nil when
    /// the model cannot load, and capture then runs on `AlertParser` alone.
    static let extractor: AlertExtractor? = try? AlertExtractor.live()

    /// Fixed identity of the one document every captured row hangs off.
    /// Not a SHA-256, so it can never collide with an imported file's.
    static let documentKey = "capture:alert"

    static func capture(_ text: String, note: String?, receivedAt: Date,
                        in ctx: ModelContext) -> Outcome {
        // Without the extractor this is exactly 1.3.0: the regex parser, a
        // memo, nothing in the ledger. A throw is treated the same way.
        guard let alert = try? extractor?.extract(text) else {
            guard var memo = AlertParser.parse(text: text, receivedAt: receivedAt) else { return Outcome() }
            memo.note = note
            return Outcome(memo: (memo, MemoStore.insert(memo, into: ctx)))
        }

        var outcome = Outcome()
        if var memo = AlertCapture.memo(from: alert, receivedAt: receivedAt) {
            memo.note = note
            outcome.memo = (memo, MemoStore.insert(memo, into: ctx))
        }
        if let row = AlertCapture.ledgerRow(from: alert, receivedAt: receivedAt) {
            outcome.row = (row, insertRow(row, into: ctx))
        }
        return outcome
    }

    /// `.duplicate` when a payment-app row with this reference and direction
    /// is already stored. Either it is an alert row with this content hash —
    /// the same payment alerted twice, by SMS and by the bank's app, say — or
    /// it came from an app export, which supersedes the alert: both are
    /// app-side, only one can reconcile against the bank row, and keeping both
    /// would count the payment twice. `ImportService` applies the same rule
    /// when the export arrives second.
    ///
    /// Checked before inserting rather than left to the unique attribute:
    /// SwiftData resolves a `contentHash` collision by upserting, which would
    /// re-point an existing row at this document and drop its category
    /// override. A failed lookup is a failure, not a miss, for the same reason.
    private static func insertRow(_ row: ParsedTransaction,
                                  into ctx: ModelContext) -> MemoStore.InsertOutcome {
        let reference = row.reference
        let direction = row.direction.rawValue
        let existing = FetchDescriptor<StoredTransaction>(
            predicate: #Predicate { $0.reference == reference && $0.directionRaw == direction })
        guard let found = try? ctx.fetch(existing) else { return .failed }
        if found.contains(where: { $0.source.kind == .paymentApp }) { return .duplicate }
        guard let document = document(covering: row.date, in: ctx) else { return .failed }

        ctx.insert(StoredTransaction(parsed: row, source: .alert, document: document))
        Queries.recomputeMatches(ctx, month: YearMonth(date: row.date))
        do {
            try ctx.save()
        } catch {
            // The main context is shared with the UI: a row left pending here
            // would be committed by whatever saves next, after the user was
            // told nothing was stored.
            ctx.rollback()
            return .failed
        }
        return .inserted
    }

    /// The "Captured alerts" document, created on first use and widened to
    /// cover `date`. One document rather than one per alert, so the rows have
    /// the owner the cascade delete expects without a document per payment.
    private static func document(covering date: Date, in ctx: ModelContext) -> StoredDocument? {
        let key = documentKey
        let descriptor = FetchDescriptor<StoredDocument>(predicate: #Predicate { $0.fileSHA256 == key })
        guard let found = try? ctx.fetch(descriptor) else { return nil }
        guard let document = found.first else {
            let document = StoredDocument(source: .alert, filename: Source.alert.displayName,
                                          fileSHA256: key, period: DatePeriod(start: date, end: date))
            ctx.insert(document)
            return document
        }
        document.periodStart = min(document.periodStart, date)
        document.periodEnd = max(document.periodEnd, date)
        return document
    }
}
