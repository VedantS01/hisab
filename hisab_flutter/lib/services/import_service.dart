/// Import pipeline, mirroring Hisab/Services/ImportService.swift:
/// file-level SHA256 duplicate check → resolver → content-hash dedup →
/// insert → reconciliation recompute for every covered month.
library;

import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
import 'memo_store.dart';
import 'queries.dart';

class ImportReport {
  final Source source;
  final int totalParsed;
  final int newCount;
  final List<YearMonth> monthsTouched;
  final bool duplicateOfExistingFile;
  const ImportReport({
    required this.source,
    required this.totalParsed,
    required this.newCount,
    required this.monthsTouched,
    required this.duplicateOfExistingFile,
  });
}

sealed class ImportServiceException implements Exception {
  const ImportServiceException();
}

class UnsupportedFormatException extends ImportServiceException {
  final FormatFingerprint fingerprint;
  const UnsupportedFormatException(this.fingerprint);
}

class UnverifiedStatementException extends ImportServiceException {
  final FormatFingerprint fingerprint;
  final String detail;
  const UnverifiedStatementException(this.fingerprint, this.detail);
}

class ImportService {
  final AppDatabase db;
  final ImportResolver resolver;
  const ImportService({required this.db, required this.resolver});

  Future<ImportReport> importBytes({
    required List<int> data,
    required String filename,
    String? password,
    Source? overrideSource,
  }) async {
    final fileHash = sha256.convert(data).toString();
    final duplicate = await _alreadyImported(fileHash);
    if (duplicate != null) return duplicate;

    final ParsedDocument parsed;
    switch (resolver.resolve(data: data, filename: filename, password: password)) {
      case ResolutionParsed(document: final doc):
        parsed = doc;
      case ResolutionPasswordRequired():
        throw const PasswordRequiredException();
      case ResolutionUnsupported(fingerprint: final fp):
        throw UnsupportedFormatException(fp);
      case ResolutionUnverified(fingerprint: final fp, detail: final detail):
        throw UnverifiedStatementException(fp, detail);
    }
    final source = overrideSource ?? parsed.source;
    return insertParsedDocument(
        parsed: parsed, source: source, filename: filename, fileHash: fileHash);
  }

  /// "Have I already taken this file in?", answered in one place. Identity is
  /// whatever the caller calls the file: its bytes for a real import, a stable
  /// key for the demo statements, whose bytes are rewritten on every load.
  Future<ImportReport?> _alreadyImported(String fileHash) async {
    final existingDocs = await db.select(db.storedDocuments).get();
    for (final doc in existingDocs) {
      if (doc.fileSha256 == fileHash) {
        return ImportReport(
            source: Source(doc.sourceRaw),
            totalParsed: 0,
            newCount: 0,
            monthsTouched: const [],
            duplicateOfExistingFile: true);
      }
    }
    return null;
  }

  /// The single insertion point, so the duplicate check is asked here too and
  /// not only on the [importBytes] path — DemoData comes straight in here.
  Future<ImportReport> insertParsedDocument({
    required ParsedDocument parsed,
    required Source source,
    required String filename,
    required String fileHash,
  }) async {
    final duplicate = await _alreadyImported(fileHash);
    if (duplicate != null) return duplicate;

    final existingHashes = <String>{};
    final txnRows = await db.select(db.storedTransactions).get();
    for (final row in txnRows) {
      if (row.sourceRaw == source.rawValue) existingHashes.add(row.contentHash);
    }
    final newIndices = Dedup.newIndices(
        incoming: parsed.transactions,
        source: source,
        existingHashes: existingHashes);

    final period = parsed.effectivePeriod;
    final documentId = newId();
    await db.into(db.storedDocuments).insert(StoredDocumentsCompanion.insert(
          id: documentId,
          sourceRaw: source.rawValue,
          filename: filename,
          fileSha256: fileHash,
          periodStartMs: period.start.toUtc().millisecondsSinceEpoch,
          periodEndMs: period.end.toUtc().millisecondsSinceEpoch,
        ));
    final inserted = <MemoMergeCandidate>[];
    final insertedRefs = <String>{};
    await db.batch((batch) {
      for (final index in newIndices) {
        final txn = parsed.transactions[index];
        final uuid = newId();
        final ref = txn.reference;
        if (ref != null && ref.isNotEmpty) {
          insertedRefs.add(_paymentKey(ref, txn.direction.name));
        }
        inserted.add(MemoMergeCandidate(
          id: uuid,
          date: txn.date,
          amountPaise: txn.amountPaise,
          direction: txn.direction,
          // The exact text `Queries.effectiveCategory` categorizes on, so the
          // VPA and payee gates see the string the rule matcher sees.
          narration: '${txn.counterparty} ${txn.narration}',
        ));
        batch.insert(
            db.storedTransactions,
            StoredTransactionsCompanion.insert(
              uuid: uuid,
              contentHash: txn.contentHash(source),
              sourceRaw: source.rawValue,
              dateMs: txn.date.toUtc().millisecondsSinceEpoch,
              amountPaise: txn.amountPaise,
              direction: txn.direction.name,
              counterparty: txn.counterparty,
              reference: Value(txn.reference),
              narration: txn.narration,
              documentId: documentId,
            ));
      }
    });

    final months = period.months;
    final recompute = {
      ...months,
      if (_supersedesAlerts(source))
        ...await _dropSupersededAlerts(insertedRefs),
    };
    for (final month in recompute) {
      await Queries.recomputeMatches(db, month);
    }

    // AFTER insertion, never before: a failed import must not retire memos.
    await _retireMemos(inserted);

    return ImportReport(
        source: source,
        totalParsed: parsed.transactions.length,
        newCount: newIndices.length,
        monthsTouched: months,
        duplicateOfExistingFile: false);
  }

  /// An app export (GPay, Paytm, BHIM, `upi:*`) is the fuller record of a
  /// payment than the alert for it, and both sit on the payment-app side, so
  /// only one of them could reconcile against the bank row — keeping both
  /// would count the payment twice. The export wins, whichever lands first:
  /// [insertCapturedAlert] skips a row an export already holds, and an export
  /// import drops the alert rows it covers.
  static bool _supersedesAlerts(Source source) =>
      source.kind == SourceKind.paymentApp && source != Source.alert;

  /// One payment's identity across sources: its reference and direction (a
  /// refund reuses the payment's reference the other way).
  static String _paymentKey(String reference, String direction) =>
      '$reference|$direction';

  /// Deletes the captured-alert rows whose payment an export just inserted,
  /// with their matches, and returns their months for reconciling again.
  Future<Set<YearMonth>> _dropSupersededAlerts(Set<String> refs) async {
    if (refs.isEmpty) return const {};
    final superseded = [
      for (final txn in await (db.select(db.storedTransactions)
            ..where((t) => t.sourceRaw.equals(Source.alert.rawValue)))
          .get())
        if (txn.reference != null &&
            refs.contains(_paymentKey(txn.reference!, txn.direction)))
          txn
    ];
    if (superseded.isEmpty) return const {};
    final uuids = [for (final txn in superseded) txn.uuid];
    await (db.delete(db.storedMatches)..where((m) => m.appUuid.isIn(uuids)))
        .go();
    await (db.delete(db.storedTransactions)..where((t) => t.uuid.isIn(uuids)))
        .go();
    return {for (final txn in superseded) YearMonth.fromDate(dateOf(txn))};
  }

  /// The one document every captured-alert row hangs off (`documentId` is NOT
  /// NULL). A fixed key rather than a file's bytes: there is no file, and the
  /// key can never equal a real SHA-256, so [_alreadyImported] never trips.
  static const capturedAlertsFileHash = 'capture:alert';

  /// A captured alert's ledger row ([AlertCapture.ledgerRow]) into the ledger
  /// as a [Source.alert] row. False when a row with its content hash is
  /// already there — the same payment alerted twice, or a re-posted alert —
  /// or when an app export already holds the payment ([_supersedesAlerts]).
  ///
  /// The row joins the persistent "Captured alerts" document, created on first
  /// use and widened to cover it, and its month is reconciled again so a
  /// statement row already imported confirms it at once. No memo is retired
  /// here: the memo from the same alert would claim its own row.
  static Future<bool> insertCapturedAlert(ParsedTransaction row,
      {required AppDatabase db}) async {
    final hash = row.contentHash(Source.alert);
    final dateMs = row.date.toUtc().millisecondsSinceEpoch;
    final inserted = await db.transaction(() async {
      final existing = await (db.select(db.storedTransactions)
            ..where((t) => t.contentHash.equals(hash)))
          .getSingleOrNull();
      if (existing != null) return false;

      final ref = row.reference;
      if (ref != null) {
        final samePayment = await (db.select(db.storedTransactions)
              ..where((t) =>
                  t.reference.equals(ref) &
                  t.direction.equals(row.direction.name)))
            .get();
        if (samePayment.any((t) => _supersedesAlerts(Source(t.sourceRaw)))) {
          return false;
        }
      }

      final doc = await (db.select(db.storedDocuments)
            ..where((d) => d.fileSha256.equals(capturedAlertsFileHash)))
          .getSingleOrNull();
      final String documentId;
      if (doc == null) {
        documentId = newId();
        await db.into(db.storedDocuments).insert(StoredDocumentsCompanion.insert(
              id: documentId,
              sourceRaw: Source.alert.rawValue,
              filename: Source.alert.displayName,
              fileSha256: capturedAlertsFileHash,
              periodStartMs: dateMs,
              periodEndMs: dateMs,
            ));
      } else {
        documentId = doc.id;
        if (dateMs < doc.periodStartMs || dateMs > doc.periodEndMs) {
          await (db.update(db.storedDocuments)
                ..where((d) => d.id.equals(doc.id)))
              .write(StoredDocumentsCompanion(
            periodStartMs: Value(min(doc.periodStartMs, dateMs)),
            periodEndMs: Value(max(doc.periodEndMs, dateMs)),
          ));
        }
      }
      await db.into(db.storedTransactions).insert(
          StoredTransactionsCompanion.insert(
            uuid: newId(),
            contentHash: hash,
            sourceRaw: Source.alert.rawValue,
            dateMs: dateMs,
            amountPaise: row.amountPaise,
            direction: row.direction.name,
            counterparty: row.counterparty,
            reference: Value(row.reference),
            narration: row.narration,
            documentId: documentId,
          ));
      return true;
    });
    if (inserted) {
      await Queries.recomputeMatches(db, YearMonth.fromDate(row.date));
    }
    return inserted;
  }

  /// Retires pending memos against statement rows that have now arrived, and
  /// drops the ones no statement is going to claim. Twin of Task 12's step in
  /// `Hisab/Services/ImportService.swift`.
  ///
  /// [candidates] is the rows THIS import inserted, matching the Swift twin
  /// and not the whole table. Two reasons, and the second is a correctness
  /// one. Rows already in the store were offered to these same memos when
  /// they landed, so re-offering them lets an unrelated month re-open a
  /// decision already made against a fuller candidate set. And
  /// [MemoMerger.merge] guarantees each candidate is claimed at most once
  /// only WITHIN one call: a row already claimed by a memo that merged on an
  /// earlier import is no longer among `memos`, so offering it again would
  /// let a second memo claim the same transaction.
  Future<void> _retireMemos(List<MemoMergeCandidate> candidates) async {
    final memoRows = await MemoStore.all(db);
    final unmerged = [
      for (final row in memoRows)
        if (row.mergedTxnUuid == null) row
    ];
    if (unmerged.isNotEmpty && candidates.isNotEmpty) {
      final assignment = MemoMerger.merge(
        memos: [for (final row in unmerged) row.asMemo],
        candidates: candidates,
      );
      for (final entry in assignment.entries) {
        await (db.update(db.storedPendingMemos)
              ..where((t) => t.captureHash.equals(entry.key)))
            .write(StoredPendingMemosCompanion(
                mergedTxnUuid: Value(entry.value)));
      }
    }

    // NOT DONE, and deliberately: Task 12 asks for the memo's note to be
    // copied onto the transaction "when the memo carries a note and the
    // transaction has none". Neither core has anywhere to put it —
    // `StoredTransactions` has no note column, and neither does SwiftData's
    // `StoredTransaction`. Adding one on this side alone would put a column
    // in the Android schema (and a v3 migration) that iOS does not have,
    // which is a worse outcome than the note staying where it is. It is not
    // lost: a merged memo is KEPT rather than expired, it carries its note,
    // and `mergedTxnUuid` points at the row it belongs to — so the note is
    // reachable from the transaction the moment either core grows a place to
    // show it.
    await MemoStore.expire(now: DateTime.now(), db: db);
  }
}
