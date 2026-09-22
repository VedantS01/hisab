/// Import pipeline, mirroring Hisab/Services/ImportService.swift:
/// file-level SHA256 duplicate check → resolver → content-hash dedup →
/// insert → reconciliation recompute for every covered month.
library;

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
    await db.batch((batch) {
      for (final index in newIndices) {
        final txn = parsed.transactions[index];
        final uuid = newId();
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
    for (final month in months) {
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
