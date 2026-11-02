/// One-time move of an iPhone's Swift-app (1.x) data into this app's drift
/// database. The native half (ios/Runner/LegacyStore.swift) reads the old
/// SwiftData store and copies the old preferences; this half writes the rows.
///
/// Runs at the top of BOTH entry points, because after the update the first
/// thing to start may be a Shortcuts automation, not the user opening the app.
/// Every insert ignores what is already there, so running twice — or racing
/// the other engine — writes nothing twice. The old store is moved aside only
/// after every one of its transactions is confirmed here.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/database.dart';
import 'password_store.dart';

abstract final class LegacyMigration {
  static const _channel = MethodChannel('hisab/legacy');

  static Future<void> runIfNeeded(AppDatabase db) async {
    if (kIsWeb || !Platform.isIOS) return;
    final String? json;
    try {
      json = await _channel.invokeMethod<String>('export');
    } on PlatformException catch (e) {
      debugPrint('legacy: export failed (${e.code})');
      return;
    }
    if (json == null) return;
    final payload = jsonDecode(json) as Map<String, Object?>;
    if (!await importPayload(db, payload)) {
      debugPrint('legacy: import incomplete; the old store stays for a retry');
      return;
    }
    final passwords = Map<String, Object?>.from(
        payload['passwords'] as Map? ?? const <String, Object?>{});
    for (final MapEntry(:key, :value) in passwords.entries) {
      if (value is String) await PasswordStore.setPassword(Source(key), value);
    }
    await _channel.invokeMethod<void>('finish');
  }

  /// For "Erase all data": what the Swift app left that is not in drift —
  /// the moved-aside store, and its copies of imported statement files.
  static Future<void> eraseLeftovers() async {
    if (kIsWeb || !Platform.isIOS) return;
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    for (final dir in [
      Directory('${support.path}/legacy-swiftdata'),
      Directory('${documents.path}/imports'),
    ]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }

  /// Writes [payload] (the shape LegacyStore.export produces) and reports
  /// whether every legacy transaction is now present, by content hash.
  @visibleForTesting
  static Future<bool> importPayload(
      AppDatabase db, Map<String, Object?> payload) async {
    List<Map<String, Object?>> rows(String key) => [
          for (final row in payload[key] as List? ?? const [])
            Map<String, Object?>.from(row as Map)
        ];
    final documents = rows('documents');
    final transactions = rows('transactions');
    final rules = rows('rules');
    final matches = rows('matches');
    final memos = rows('memos');
    final pinned = [for (final m in payload['pinnedMonths'] as List? ?? []) '$m'];

    // SwiftData let a transaction exist without a document; drift does not.
    const orphanDocumentId = 'legacy-orphans';
    final orphans = transactions.where((t) => t['documentId'] == null).toList();

    await db.transaction(() async {
      await db.batch((b) {
        for (final d in documents) {
          b.insert(
              db.storedDocuments,
              StoredDocumentsCompanion.insert(
                id: d['id'] as String,
                sourceRaw: d['sourceRaw'] as String,
                filename: d['filename'] as String,
                fileSha256: d['fileSha256'] as String,
                periodStartMs: d['periodStartMs'] as int,
                periodEndMs: d['periodEndMs'] as int,
                importedAtMs: Value(d['importedAtMs'] as int?),
              ),
              mode: InsertMode.insertOrIgnore);
        }
        if (orphans.isNotEmpty) {
          final dates = [for (final t in orphans) t['dateMs'] as int];
          b.insert(
              db.storedDocuments,
              StoredDocumentsCompanion.insert(
                id: orphanDocumentId,
                sourceRaw: orphans.first['sourceRaw'] as String,
                filename: 'Earlier imports',
                fileSha256: 'legacy:orphans',
                periodStartMs: dates.reduce((a, b) => a < b ? a : b),
                periodEndMs: dates.reduce((a, b) => a > b ? a : b),
              ),
              mode: InsertMode.insertOrIgnore);
        }
        for (final t in transactions) {
          b.insert(
              db.storedTransactions,
              StoredTransactionsCompanion.insert(
                uuid: t['uuid'] as String,
                contentHash: t['contentHash'] as String,
                sourceRaw: t['sourceRaw'] as String,
                dateMs: t['dateMs'] as int,
                amountPaise: t['amountPaise'] as int,
                direction: t['direction'] as String,
                counterparty: t['counterparty'] as String,
                reference: Value(t['reference'] as String?),
                narration: t['narration'] as String,
                categoryOverride: Value(t['categoryOverride'] as String?),
                documentId: t['documentId'] as String? ?? orphanDocumentId,
              ),
              mode: InsertMode.insertOrIgnore);
        }
      });

      // A transaction this database already had (a capture that ran before
      // the migration did) keeps its own uuid; references follow the hash.
      final hashes = {for (final t in transactions) t['contentHash'] as String};
      final present = await (db.select(db.storedTransactions)
            ..where((t) => t.contentHash.isIn(hashes)))
          .get();
      final uuidByHash = {for (final t in present) t.contentHash: t.uuid};
      final uuidFor = {
        for (final t in transactions)
          t['uuid'] as String: uuidByHash[t['contentHash']] ?? t['uuid'] as String
      };

      final existingPatterns = {
        for (final r in await db.select(db.storedCategoryRules).get())
          r.pattern.toLowerCase()
      };
      await db.batch((b) {
        for (final r in rules) {
          if (existingPatterns.contains((r['pattern'] as String).toLowerCase())) {
            continue;
          }
          b.insert(
              db.storedCategoryRules,
              StoredCategoryRulesCompanion.insert(
                id: r['id'] as String,
                pattern: r['pattern'] as String,
                category: r['category'] as String,
                sortOrder: r['sortOrder'] as int,
              ),
              mode: InsertMode.insertOrIgnore);
        }
        for (final m in matches) {
          final app = uuidFor[m['appUuid']] ?? m['appUuid'] as String;
          final bank = uuidFor[m['bankUuid']] ?? m['bankUuid'] as String;
          b.insert(
              db.storedMatches,
              StoredMatchesCompanion.insert(
                id: '$app|$bank',
                monthKey: m['monthKey'] as String,
                appUuid: app,
                bankUuid: bank,
                tier: m['tier'] as String,
              ),
              mode: InsertMode.insertOrIgnore);
        }
        for (final key in pinned) {
          b.insert(db.pinnedMonths, PinnedMonthsCompanion.insert(monthKey: key),
              mode: InsertMode.insertOrIgnore);
        }
        for (final m in memos) {
          final merged = m['mergedTxnUuid'] as String?;
          b.insert(
              db.storedPendingMemos,
              StoredPendingMemosCompanion.insert(
                captureHash: m['captureHash'] as String,
                amountPaise: m['amountPaise'] as int,
                direction: m['direction'] as String,
                payee: m['payee'] as String,
                payeeNormalized: m['payeeNormalized'] as String,
                vpa: Value(m['vpa'] as String?),
                accountTail: Value(m['accountTail'] as String?),
                dateMs: m['dateMs'] as int,
                capturedAtMs: m['capturedAtMs'] as int,
                note: Value(m['note'] as String?),
                assignedCategory: Value(m['assignedCategory'] as String?),
                mergedTxnUuid: Value(merged == null ? null : uuidFor[merged] ?? merged),
                notifiedAtMs: Value(m['notifiedAtMs'] as int?),
              ),
              mode: InsertMode.insertOrIgnore);
        }
      });
    });

    final stored = await (db.select(db.storedTransactions)
          ..where((t) => t.contentHash
              .isIn([for (final t in transactions) t['contentHash'] as String])))
        .get();
    return stored.length == transactions.length;
  }
}
