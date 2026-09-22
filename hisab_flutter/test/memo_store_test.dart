// Pending-memo storage, and the schema-v1 -> v2 migration.
//
// The load-bearing test here is `an existing v1 database upgrades`: it opens a
// database at the OLD schema version with real rows in it and lets drift
// migrate. A fresh install is created at v2 by drift's onCreate and would pass
// even with the MigrationStrategy deleted, so a fresh-install test proves
// nothing about the only case that exists in the field — an upgrade.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_prefs.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The schema as it shipped at v1 — no `stored_pending_memos`. Handwritten
/// from lib/storage/database.dart at the v1 revision, because drift's
/// schema-dump tooling is not wired into this project.
const v1Schema = '''
CREATE TABLE stored_documents (
  id TEXT NOT NULL,
  source_raw TEXT NOT NULL,
  filename TEXT NOT NULL,
  file_sha256 TEXT NOT NULL,
  period_start_ms INTEGER NOT NULL,
  period_end_ms INTEGER NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE stored_transactions (
  uuid TEXT NOT NULL,
  content_hash TEXT NOT NULL UNIQUE,
  source_raw TEXT NOT NULL,
  date_ms INTEGER NOT NULL,
  amount_paise INTEGER NOT NULL,
  direction TEXT NOT NULL,
  counterparty TEXT NOT NULL,
  reference TEXT NULL,
  narration TEXT NOT NULL,
  category_override TEXT NULL,
  document_id TEXT NOT NULL,
  PRIMARY KEY (uuid)
);
CREATE TABLE stored_category_rules (
  id TEXT NOT NULL,
  pattern TEXT NOT NULL,
  category TEXT NOT NULL,
  sort_order INTEGER NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE stored_matches (
  id TEXT NOT NULL,
  month_key TEXT NOT NULL,
  app_uuid TEXT NOT NULL,
  bank_uuid TEXT NOT NULL,
  tier TEXT NOT NULL,
  PRIMARY KEY (id)
);
CREATE TABLE pinned_months (
  month_key TEXT NOT NULL,
  PRIMARY KEY (month_key)
);
''';

/// A database that already holds a user's data at schema v1, exactly as an
/// installed copy of the previous release would. The `setup` callback runs on
/// the raw sqlite connection before drift reads `user_version`, so drift sees
/// a v1 database and takes the upgrade path.
AppDatabase openUpgradedFromV1() =>
    AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute(v1Schema);
      raw.execute('''
INSERT INTO stored_documents
  (id, source_raw, filename, file_sha256, period_start_ms, period_end_ms)
VALUES ('doc-1', 'hdfc', 'april.csv', 'abc123', 1000, 2000);
''');
      raw.execute('''
INSERT INTO stored_transactions
  (uuid, content_hash, source_raw, date_ms, amount_paise, direction,
   counterparty, reference, narration, category_override, document_id)
VALUES ('txn-1', 'hash-1', 'hdfc', 1500, 12500, 'debit',
        'Blue Tokai', 'R1', 'UPI/R1/coffee', NULL, 'doc-1');
''');
      raw.execute("INSERT INTO pinned_months (month_key) VALUES ('2026-04');");
      raw.execute('PRAGMA user_version = 1;');
    }));

DateTime ist(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

PendingMemo memoAt(
  DateTime when, {
  int amountPaise = 45000,
  String payee = 'Blue Tokai',
  String? vpa = 'bluetokai@okaxis',
  Direction direction = Direction.debit,
  DateTime? capturedAt,
}) =>
    PendingMemo(
      amountPaise: amountPaise,
      direction: direction,
      payee: payee,
      vpa: vpa,
      accountTail: '1234',
      date: when,
      capturedAt: capturedAt ?? when,
      note: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('schema migration v1 -> v2', () {
    test('an existing v1 database upgrades: old rows survive, memos work',
        () async {
      final db = openUpgradedFromV1();
      addTearDown(db.close);

      // Force drift to open the database and run the migration.
      final docs = await db.select(db.storedDocuments).get();
      expect(docs.map((d) => d.id), ['doc-1'],
          reason: 'the pre-existing document must survive the migration');

      final txns = await db.select(db.storedTransactions).get();
      expect(txns, hasLength(1));
      expect(txns.single.uuid, 'txn-1');
      expect(txns.single.amountPaise, 12500);
      expect(txns.single.counterparty, 'Blue Tokai');
      expect(txns.single.contentHash, 'hash-1',
          reason: 'dedup identity must not be disturbed by the migration');

      final pins = await db.select(db.pinnedMonths).get();
      expect(pins.map((p) => p.monthKey), ['2026-04']);

      // ...and the table the migration was for actually exists.
      final inserted =
          await MemoStore.insert(memoAt(ist(2026, 9, 22, 9, 15)), db: db);
      expect(inserted, isTrue);
      expect(await MemoStore.all(db), hasLength(1));

      final version = await db
          .customSelect('PRAGMA user_version;')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      expect(version, 2, reason: 'the upgrade must record the new version');
    });

    test('a fresh install is created at v2 with the memo table', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(await MemoStore.insert(memoAt(ist(2026, 9, 22)), db: db), isTrue);
      final version = await db
          .customSelect('PRAGMA user_version;')
          .map((row) => row.read<int>('user_version'))
          .getSingle();
      expect(version, 2);
    });
  });

  group('MemoStore', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('a repeated capture of the same alert does not make a second memo',
        () async {
      final memo = memoAt(ist(2026, 9, 22, 9, 15));
      expect(await MemoStore.insert(memo, db: db), isTrue);

      // Android re-posts the same notification as an update; capture time
      // moves, the alert does not.
      final again = memoAt(ist(2026, 9, 22, 9, 15),
          capturedAt: ist(2026, 9, 22, 11, 30));
      expect(await MemoStore.insert(again, db: db), isFalse);
      expect(await MemoStore.all(db), hasLength(1));
    });

    test('a categorization survives a duplicate capture', () async {
      final memo = memoAt(ist(2026, 9, 22, 9, 15));
      await MemoStore.insert(memo, db: db);
      final stored = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      await MemoStore.assign(category: 'Food', memo: stored, db: db);

      await MemoStore.insert(memo, db: db);

      final after = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      expect(after.assignedCategory, 'Food',
          reason: 'a re-capture must never clobber the user\'s own label');
    });

    test('pending excludes labelled and merged memos, newest first', () async {
      final older = memoAt(ist(2026, 9, 20, 9, 0));
      final newer = memoAt(ist(2026, 9, 22, 9, 0), amountPaise: 9900);
      final labelled = memoAt(ist(2026, 9, 21, 9, 0), amountPaise: 15000);
      final merged = memoAt(ist(2026, 9, 21, 10, 0), amountPaise: 22200);
      for (final m in [older, newer, labelled, merged]) {
        expect(await MemoStore.insert(m, db: db), isTrue);
      }

      await MemoStore.assign(
          category: 'Food',
          memo: (await MemoStore.find(hash: labelled.captureHash, db: db))!,
          db: db);
      await (db.update(db.storedPendingMemos)
            ..where((t) => t.captureHash.equals(merged.captureHash)))
          .write(const StoredPendingMemosCompanion(
              mergedTxnUuid: Value('txn-1')));

      final rows = await MemoStore.pending(db);
      expect(rows.map((r) => r.captureHash),
          [newer.captureHash, older.captureHash]);
    });

    test('find returns null for an unknown hash', () async {
      expect(await MemoStore.find(hash: 'nope', db: db), isNull);
    });

    test('expire drops unmerged memos past 45 days and keeps the rest',
        () async {
      final fresh = memoAt(ist(2026, 9, 22), amountPaise: 1000);
      final old = memoAt(ist(2026, 7, 1), amountPaise: 2000);
      final oldButMerged = memoAt(ist(2026, 7, 1), amountPaise: 3000);
      for (final m in [fresh, old, oldButMerged]) {
        await MemoStore.insert(m, db: db);
      }
      await (db.update(db.storedPendingMemos)
            ..where((t) => t.captureHash.equals(oldButMerged.captureHash)))
          .write(const StoredPendingMemosCompanion(
              mergedTxnUuid: Value('txn-1')));

      // 2026-07-01 -> 2026-09-22 is 83 days; 2026-09-22 is day zero.
      await MemoStore.expire(now: ist(2026, 9, 22), db: db);

      final left = (await MemoStore.all(db)).map((r) => r.captureHash).toSet();
      expect(left, {fresh.captureHash, oldButMerged.captureHash});
    });

    test('a stored memo reads back as the memo that was captured', () async {
      final memo = memoAt(ist(2026, 9, 22, 9, 15));
      await MemoStore.insert(memo, db: db);
      final stored = (await MemoStore.find(hash: memo.captureHash, db: db))!;

      expect(stored.asMemo, memo);
      expect(stored.amountPaise, isA<int>(),
          reason: 'money is integer paise, never a double');
      expect(stored.payeeNormalized, memo.payeeNormalized);
    });
  });

  group('CapturePrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('capture is off until the user opts in', () async {
      expect(await CapturePrefs.isEnabled(), isFalse);
      await CapturePrefs.setEnabled(true);
      expect(await CapturePrefs.isEnabled(), isTrue);
    });

    test('the two health timestamps are independent', () async {
      expect(await CapturePrefs.lastCaptureAt(), isNull);
      expect(await CapturePrefs.lastAttemptAt(), isNull);

      final attempt = ist(2026, 9, 22, 9, 15);
      await CapturePrefs.setLastAttemptAt(attempt);
      expect(await CapturePrefs.lastAttemptAt(), attempt);
      expect(await CapturePrefs.lastCaptureAt(), isNull,
          reason: 'an alert that failed to parse is not a capture');

      final capture = ist(2026, 9, 22, 10, 0);
      await CapturePrefs.setLastCaptureAt(capture);
      expect(await CapturePrefs.lastCaptureAt(), capture);
    });

    test('the notification count resets on the IST day boundary', () async {
      final lateNight = ist(2026, 9, 22, 23, 50);
      await CapturePrefs.recordNotification(lateNight);
      await CapturePrefs.recordNotification(lateNight);
      expect(await CapturePrefs.notificationsSentToday(lateNight), 2);

      final afterMidnight = ist(2026, 9, 23, 0, 5);
      expect(await CapturePrefs.notificationsSentToday(afterMidnight), 0);
      await CapturePrefs.recordNotification(afterMidnight);
      expect(await CapturePrefs.notificationsSentToday(afterMidnight), 1);
      expect(await CapturePrefs.notificationsSentToday(lateNight), 0,
          reason: 'yesterday\'s count is gone, not merged');
    });
  });
}
