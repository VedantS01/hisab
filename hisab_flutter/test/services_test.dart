import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/demo_data.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/queries.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';

const demoCsv = 'hisab-demo-csv,v1\n'
    'period,2026-04-01,2026-04-30\n'
    '2026-04-02,12500,debit,Blue Tokai,R1,UPI/R1/coffee\n'
    '2026-04-05,500000,credit,Acme Corp,R2,salary\n';

const bankCsv = 'hisab-demo-csv,v1\n'
    'period,2026-04-01,2026-04-30\n'
    '2026-04-02,12500,debit,BLUE TOKAI POS,R1,POS blue tokai\n'
    '2026-04-07,90000,debit,LANDLORD,RB9,rent transfer\n';

void main() {
  late AppDatabase db;
  late ImportService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = ImportService(
        db: db,
        resolver:
            ImportResolver(registry: liveRegistry(), specs: const []));
  });

  tearDown(() async => db.close());

  test('import inserts, re-import dedups, overlapping file dedups', () async {
    final report = await service.importBytes(
        data: utf8.encode(demoCsv), filename: 'demo.csv');
    expect(report.newCount, 2);
    expect(report.monthsTouched, [YearMonth(2026, 4)]);

    final again = await service.importBytes(
        data: utf8.encode(demoCsv), filename: 'demo.csv');
    expect(again.duplicateOfExistingFile, isTrue);

    // Same rows in a differently-named file: file hash differs, rows dedup.
    final overlapping = await service.importBytes(
        data: utf8.encode('$demoCsv\n'), filename: 'demo2.csv');
    expect(overlapping.newCount, 0);
    expect(overlapping.totalParsed, 2);
  });

  test('reconciliation matches app vs bank and hides evidence', () async {
    await service.importBytes(data: utf8.encode(demoCsv), filename: 'app.csv');
    await service.importBytes(
        data: utf8.encode(bankCsv),
        filename: 'bank.csv',
        overrideSource: Source.hdfc);

    final matches = await db.select(db.storedMatches).get();
    expect(matches.length, 1, reason: 'R1 matches by reference');
    expect(matches.single.tier, 'reference');

    final txns = await db.select(db.storedTransactions).get();
    final visible = Queries.visible(txns, matches);
    // 2 app txns + 1 unmatched bank txn (rent) visible; matched bank hidden.
    expect(visible.length, 3);

    final ruleList = [
      const CategoryRule(id: 'r', pattern: 'blue tokai', category: 'Coffee')
    ];
    final analytics = Queries.analytics(txns, matches, CategoryMatcher(ruleList));
    final stats = Analytics.monthStats(analytics, YearMonth(2026, 4));
    // Spend: 125.00 (coffee, counted once) + 900.00 (rent, Miscellaneous).
    expect(stats.spendPaise, 12500 + 90000);
    expect(stats.incomePaise, 500000);
    final breakdown =
        Analytics.categoryBreakdown(analytics, YearMonth(2026, 4), top: 5);
    expect(breakdown.map((s) => s.category).toSet(),
        {'Coffee', Categorizer.miscellaneous});
  });

  test('additive rule seeding never touches existing rules', () async {
    final ruleset = Ruleset.fromJsonString(
        File('assets/rulesets/india-default.json').readAsStringSync());
    final first = await Queries.categoryRules(db, ruleset);
    expect(first.length, ruleset.rules.length);

    // User edits one rule's category; reseeding must not revert it.
    final swiggy = (await db.select(db.storedCategoryRules).get())
        .firstWhere((r) => r.pattern == 'swiggy');
    await (db.update(db.storedCategoryRules)
          ..where((r) => r.id.equals(swiggy.id)))
        .write(const StoredCategoryRulesCompanion(
            category: Value('My Custom Food')));

    final second = await Queries.categoryRules(db, ruleset);
    expect(second.length, ruleset.rules.length);
    expect(second.firstWhere((r) => r.pattern == 'swiggy').category,
        'My Custom Food');
  });

  test('unsupported bytes raise the request-flow exception', () async {
    await expectLater(
        service.importBytes(data: [0, 1, 2], filename: 'x.xlsx'),
        throwsA(isA<UnsupportedFormatException>()));
  });

  test('insightRecords carries row ids and excludes matched bank rows',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.storedDocuments).insert(StoredDocumentsCompanion.insert(
          id: 'doc-1',
          sourceRaw: 'gpay',
          filename: 'demo.csv',
          fileSha256: 'hash-1',
          periodStartMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          periodEndMs: DateTime.utc(2026, 8, 31).millisecondsSinceEpoch,
        ));
    await db.into(db.storedTransactions).insert(
        StoredTransactionsCompanion.insert(
          uuid: 'uuid-1',
          documentId: 'doc-1',
          sourceRaw: 'gpay',
          dateMs: DateTime.utc(2026, 8, 12).millisecondsSinceEpoch,
          amountPaise: 45000,
          direction: 'debit',
          counterparty: 'Swiggy',
          narration: 'UPI payment',
          contentHash: 'ch-1',
        ));
    // Bank-side evidence for the same spend, reconciled against uuid-1.
    // Matched bank rows must be excluded from insightRecords.
    await db.into(db.storedTransactions).insert(
        StoredTransactionsCompanion.insert(
          uuid: 'uuid-2',
          documentId: 'doc-1',
          sourceRaw: 'hdfc',
          dateMs: DateTime.utc(2026, 8, 12).millisecondsSinceEpoch,
          amountPaise: 45000,
          direction: 'debit',
          counterparty: 'SWIGGY POS',
          narration: 'POS swiggy',
          contentHash: 'ch-2',
        ));
    await db.into(db.storedMatches).insert(StoredMatchesCompanion.insert(
          id: 'match-1',
          monthKey: '2026-08',
          appUuid: 'uuid-1',
          bankUuid: 'uuid-2',
          tier: 'reference',
        ));

    final txns = await db.select(db.storedTransactions).get();
    final matches = await db.select(db.storedMatches).get();
    final records = Queries.insightRecords(txns, matches, CategoryMatcher(const []));
    expect(records.length, 1);
    expect(records.first.id, 'uuid-1');
    expect(records.first.merchant, 'Swiggy');
    expect(records.first.amountPaise, 45000);
    expect(records.any((r) => r.id == 'uuid-2'), isFalse,
        reason: 'matched bank row must be excluded');

    final docs = await db.select(db.storedDocuments).get();
    expect(Queries.insightPeriods(docs).length, 1);
  });

  Map<String, String> demoTexts() => {
        for (final name in ['demo-gpay.csv', 'demo-hdfc.csv', 'demo-idfc.csv'])
          'assets/demo/$name': File('assets/demo/$name').readAsStringSync(),
      };

  // "Load demo data" is a button a user can press twice, and the statements are
  // rewritten to the current month on every load. Pressing it again must leave
  // exactly one demo set — not two — and that set must be anchored to *now*,
  // not frozen at whenever it was first loaded.
  test('loading the demo again replaces it and re-anchors to today', () async {
    Future<(int, int)> counts() async => (
          (await db.select(db.storedDocuments).get()).length,
          (await db.select(db.storedTransactions).get()).length,
        );
    Future<int> newestMonth() async {
      final txns = await db.select(db.storedTransactions).get();
      return txns
          .map((t) => t.dateMs)
          .reduce((a, b) => a > b ? a : b);
    }

    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2026, 9, 21));
    final afterFirst = await counts();
    expect(afterFirst.$1, 3, reason: 'one document per demo statement');
    expect(afterFirst.$2, greaterThan(200));
    final firstNewest = await newestMonth();

    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2026, 9, 21));
    expect(await counts(), afterFirst, reason: 'same-month reload: same totals');
    expect(await newestMonth(), firstNewest, reason: 'and the same dates');

    for (final later in [
      DateTime.utc(2026, 12, 15),
      DateTime.utc(2027, 6, 2), // crosses a year boundary
    ]) {
      await DemoData.loadTexts(service, demoTexts(), now: later);
      expect(await counts(), afterFirst,
          reason: 'reload on ${istDayString(later)} must replace, not add');
      expect(YearMonth.fromDate(
              DateTime.fromMillisecondsSinceEpoch(await newestMonth(), isUtc: true)),
          YearMonth.fromDate(later),
          reason: 'reload must re-anchor the demo to the day it was loaded');
    }

    final txns = await db.select(db.storedTransactions).get();
    expect(txns.map((t) => t.contentHash).toSet(), hasLength(txns.length),
        reason: 'no two stored rows may share a content hash');
  });

  // Nothing cascades in this schema — documentId is a plain column — so the
  // refresh deletes rows by hand, and a missed one would be invisible until it
  // corrupted a total.
  test('a demo refresh leaves no orphaned transactions or matches', () async {
    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2026, 9, 21));
    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2027, 1, 20));

    final docIds =
        (await db.select(db.storedDocuments).get()).map((d) => d.id).toSet();
    final txns = await db.select(db.storedTransactions).get();
    final uuids = txns.map((t) => t.uuid).toSet();

    expect(txns.where((t) => !docIds.contains(t.documentId)), isEmpty,
        reason: 'every transaction must still belong to a live document');
    final matches = await db.select(db.storedMatches).get();
    expect(
        matches.where(
            (m) => !uuids.contains(m.appUuid) || !uuids.contains(m.bankUuid)),
        isEmpty,
        reason: 'every match must still point at two live transactions');
    expect(matches, isNotEmpty, reason: 'the demo reconciles, so some survive');
  });

  test('a demo refresh leaves the user\'s own import untouched', () async {
    // A real statement of the user's, imported before they ever tap the demo.
    final mine = await service.importBytes(
        data: utf8.encode(demoCsv), filename: 'my-statement.csv');
    expect(mine.newCount, 2);
    final mineDoc = (await db.select(db.storedDocuments).get())
        .firstWhere((d) => d.filename == 'my-statement.csv');
    final mineTxns = (await db.select(db.storedTransactions).get())
        .where((t) => t.documentId == mineDoc.id)
        .map((t) => t.uuid)
        .toSet();
    expect(mineTxns, hasLength(2));

    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2026, 9, 21));
    await DemoData.loadTexts(service, demoTexts(), now: DateTime.utc(2026, 12, 15));

    final docs = await db.select(db.storedDocuments).get();
    expect(docs.where((d) => d.id == mineDoc.id), hasLength(1),
        reason: "the user's document must survive a demo refresh");
    expect(docs, hasLength(4), reason: 'their one plus the three demo slots');
    final survivors = (await db.select(db.storedTransactions).get())
        .where((t) => t.documentId == mineDoc.id)
        .map((t) => t.uuid)
        .toSet();
    expect(survivors, mineTxns,
        reason: "the user's rows must survive, same rows, same ids");
  });
}
