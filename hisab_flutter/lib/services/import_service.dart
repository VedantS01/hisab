/// Import pipeline, mirroring Hisab/Services/ImportService.swift:
/// file-level SHA256 duplicate check → resolver → content-hash dedup →
/// insert → reconciliation recompute for every covered month.
library;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
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

  Future<ImportReport> insertParsedDocument({
    required ParsedDocument parsed,
    required Source source,
    required String filename,
    required String fileHash,
  }) async {
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
    return ImportReport(
        source: source,
        totalParsed: parsed.transactions.length,
        newCount: newIndices.length,
        monthsTouched: months,
        duplicateOfExistingFile: false);
  }
}
