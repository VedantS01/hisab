import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final analytics = Queries.analytics(txns, matches, ruleList);
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
}
