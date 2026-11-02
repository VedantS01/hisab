// The drift half of the Swift-app migration, against the JSON shape
// ios/Runner/LegacyStore.swift exports. The native half is exercised on the
// simulator (a Swift build's store, upgraded in place).
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/legacy_migration.dart';
import 'package:hisab/storage/database.dart';

Map<String, Object?> payload() => {
      'documents': [
        {
          'id': 'DOC-1', 'sourceRaw': 'hdfc', 'filename': 'hdfc-sep.pdf',
          'fileSha256': 'abc', 'periodStartMs': 1000, 'periodEndMs': 2000,
          'importedAtMs': 3000,
        },
      ],
      'transactions': [
        {
          'uuid': 'BANK-1', 'contentHash': 'h-bank', 'sourceRaw': 'hdfc',
          'dateMs': 1500, 'amountPaise': 45000, 'direction': 'debit',
          'counterparty': 'SWIGGY', 'reference': '627775786529',
          'narration': 'UPI-SWIGGY', 'categoryOverride': 'Food',
          'documentId': 'DOC-1',
        },
        {
          'uuid': 'APP-1', 'contentHash': 'h-app', 'sourceRaw': 'gpay',
          'dateMs': 1500, 'amountPaise': 45000, 'direction': 'debit',
          'counterparty': 'Swiggy', 'reference': '627775786529',
          'narration': '', 'categoryOverride': null, 'documentId': null,
        },
      ],
      'rules': [
        {'id': 'RULE-1', 'pattern': 'swiggy', 'category': 'Food', 'sortOrder': 0},
      ],
      'matches': [
        {'appUuid': 'APP-1', 'bankUuid': 'BANK-1', 'tier': 'reference',
          'monthKey': '2026-09'},
      ],
      'pinnedMonths': ['2026-10'],
      'memos': [
        {
          'captureHash': 'cap-1', 'amountPaise': 45000, 'direction': 'debit',
          'payee': 'Swiggy', 'payeeNormalized': 'swiggy', 'vpa': null,
          'accountTail': '1234', 'dateMs': 1500, 'capturedAtMs': 1600,
          'note': 'lunch', 'assignedCategory': 'Food',
          'mergedTxnUuid': 'BANK-1', 'notifiedAtMs': null,
        },
      ],
      'passwords': {'hdfc': 'secret'},
    };

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('every table arrives, with dates and the override intact', () async {
    expect(await LegacyMigration.importPayload(db, payload()), isTrue);

    final doc = await (db.select(db.storedDocuments)
          ..where((d) => d.id.equals('DOC-1')))
        .getSingle();
    expect(doc.importedAtMs, 3000);
    final bank = await (db.select(db.storedTransactions)
          ..where((t) => t.uuid.equals('BANK-1')))
        .getSingle();
    expect(bank.categoryOverride, 'Food');
    expect(bank.documentId, 'DOC-1');
    expect((await db.select(db.storedCategoryRules).get()).single.pattern,
        'swiggy');
    expect((await db.select(db.storedMatches).get()).single.id,
        'APP-1|BANK-1');
    expect((await db.select(db.pinnedMonths).get()).single.monthKey,
        '2026-10');
    final memo = (await db.select(db.storedPendingMemos).get()).single;
    expect(memo.mergedTxnUuid, 'BANK-1');
    expect(memo.note, 'lunch');
  });

  test('a transaction with no document gets one, not dropped', () async {
    await LegacyMigration.importPayload(db, payload());
    final app = await (db.select(db.storedTransactions)
          ..where((t) => t.uuid.equals('APP-1')))
        .getSingle();
    expect(app.documentId, 'legacy-orphans');
    final orphanDoc = await (db.select(db.storedDocuments)
          ..where((d) => d.id.equals('legacy-orphans')))
        .getSingle();
    expect(orphanDoc.periodStartMs, 1500);
  });

  test('a row captured before the migration keeps its id; links follow it',
      () async {
    // The Shortcuts engine filed this alert before the app ever opened.
    await db.into(db.storedDocuments).insert(StoredDocumentsCompanion.insert(
        id: 'NEW-DOC', sourceRaw: 'hdfc', filename: 'x', fileSha256: 'y',
        periodStartMs: 0, periodEndMs: 0));
    await db.into(db.storedTransactions).insert(
        StoredTransactionsCompanion.insert(
            uuid: 'NEW-BANK', contentHash: 'h-bank', sourceRaw: 'hdfc',
            dateMs: 1500, amountPaise: 45000, direction: 'debit',
            counterparty: 'SWIGGY', narration: '', documentId: 'NEW-DOC',
            reference: const Value('627775786529')));

    expect(await LegacyMigration.importPayload(db, payload()), isTrue);
    expect((await db.select(db.storedMatches).get()).single.bankUuid,
        'NEW-BANK');
    expect((await db.select(db.storedPendingMemos).get()).single.mergedTxnUuid,
        'NEW-BANK');
    expect(await db.select(db.storedTransactions).get(), hasLength(2));
  });

  test('running twice writes nothing twice', () async {
    await LegacyMigration.importPayload(db, payload());
    expect(await LegacyMigration.importPayload(db, payload()), isTrue);
    expect(await db.select(db.storedTransactions).get(), hasLength(2));
    expect(await db.select(db.storedCategoryRules).get(), hasLength(1));
    expect(await db.select(db.storedPendingMemos).get(), hasLength(1));
  });
}
