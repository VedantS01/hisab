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
    await db.batch((batch) {
      for (final index in newIndices) {
        final txn = parsed.transactions[index];
        batch.insert(
            db.storedTransactions,
            StoredTransactionsCompanion.insert(
              uuid: newId(),
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
    await _retireMemos();

    return ImportReport(
        source: source,
        totalParsed: parsed.transactions.length,
        newCount: newIndices.length,
        monthsTouched: months,
        duplicateOfExistingFile: false);
  }

  /// Retires pending memos against statement rows that have now arrived, and
  /// drops the ones no statement is going to claim. Twin of Task 12's iOS
  /// step in `ImportService.swift`.
  ///
  /// The candidate set is EVERY stored transaction, not only the rows this
  /// import added. A memo captured today can be claimed by a statement
  /// imported last week only if that row is offered, and
  /// [MemoMerger.merge]'s assignment is global by design — closest pair
  /// first, each memo and each candidate used at most once.
  ///
  /// The narration handed to the merger is `"$counterparty $narration"`, the
  /// same concatenation [Queries.effectiveCategory] categorizes with, so VPA
  /// matching sees exactly what categorization sees.
  Future<void> _retireMemos() async {
    final memoRows = await MemoStore.all(db);
    final unmerged = [
      for (final row in memoRows)
        if (row.mergedTxnUuid == null) row
    ];
    if (unmerged.isNotEmpty) {
      final txns = await db.select(db.storedTransactions).get();
      final assignment = MemoMerger.merge(
        memos: [for (final row in unmerged) row.asMemo],
        candidates: [
          for (final txn in txns)
            MemoMergeCandidate(
              id: txn.uuid,
              date: dateOf(txn),
              amountPaise: txn.amountPaise,
              direction: directionOf(txn),
              narration: '${txn.counterparty} ${txn.narration}',
            )
        ],
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
