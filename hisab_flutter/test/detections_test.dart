// Detections: memos that are not ledger rows yet, and the ways out of them.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/detections.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_agents/hisab_agents.dart' show Detection;
import 'package:hisab_core/hisab_core.dart';

DateTime ist(int year, int month, int day, [int hour = 12]) =>
    DateTime.utc(year, month, day, hour).subtract(istOffset);

PendingMemo memoFor(
        {int amountPaise = 45000,
        String payee = 'QWERTYSHOP',
        DateTime? at,
        Direction direction = Direction.debit}) =>
    PendingMemo(
      amountPaise: amountPaise,
      direction: direction,
      payee: payee,
      vpa: null,
      accountTail: '1234',
      date: at ?? ist(2026, 9, 22),
      capturedAt: at ?? ist(2026, 9, 22),
    );

ParsedTransaction rowFor(
        {int amountPaise = 45000,
        String reference = '627775786529',
        DateTime? at,
        Direction direction = Direction.debit}) =>
    ParsedTransaction(
      date: at ?? ist(2026, 9, 22),
      amountPaise: amountPaise,
      direction: direction,
      counterparty: 'QWERTYSHOP',
      reference: reference,
      narration: '',
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<StoredPendingMemo> stored(PendingMemo memo) async =>
      (await MemoStore.find(hash: memo.captureHash, db: db))!;
  Future<StoredTransaction> txn(String uuid) =>
      (db.select(db.storedTransactions)..where((t) => t.uuid.equals(uuid)))
          .getSingle();

  test('a memo with no row is a detection; linking, dismissing end it',
      () async {
    final older = memoFor(payee: 'A', at: ist(2026, 9, 20));
    final newer = memoFor(payee: 'B', at: ist(2026, 9, 22));
    final third = memoFor(payee: 'C', at: ist(2026, 9, 21));
    for (final m in [older, newer, third]) {
      await MemoStore.insert(m, db: db);
    }
    expect([for (final m in Detections.open(await MemoStore.all(db))) m.payee],
        ['B', 'C', 'A']);

    final id = (await ImportService.insertCapturedAlert(rowFor(), db: db))!;
    await Detections.link(newer.captureHash, id, db: db);
    await Detections.dismiss(older.captureHash, db: db);
    expect([for (final m in Detections.open(await MemoStore.all(db))) m.payee],
        ['C']);
  });

  test('a link gives the row the category the user set on the detection',
      () async {
    final memo = memoFor();
    await MemoStore.insert(memo, db: db);
    await MemoStore.assign(category: 'Food', memo: await stored(memo), db: db);
    final id = (await ImportService.insertCapturedAlert(rowFor(), db: db))!;

    await Detections.link(memo.captureHash, id, db: db);

    expect((await txn(id)).categoryOverride, 'Food');
  });

  test("a link never overwrites the row's own category", () async {
    final memo = memoFor();
    await MemoStore.insert(memo, db: db);
    await MemoStore.assign(category: 'Food', memo: await stored(memo), db: db);
    final id = (await ImportService.insertCapturedAlert(rowFor(), db: db))!;
    await (db.update(db.storedTransactions)..where((t) => t.uuid.equals(id)))
        .write(const StoredTransactionsCompanion(
            categoryOverride: Value('Gifts')));

    await Detections.link(memo.captureHash, id, db: db);

    expect((await txn(id)).categoryOverride, 'Gifts');
  });

  test('labelling a linked memo labels its row, and follows a change of mind',
      () async {
    final memo = memoFor();
    await MemoStore.insert(memo, db: db);
    final id = (await ImportService.insertCapturedAlert(rowFor(), db: db))!;
    await Detections.link(memo.captureHash, id, db: db);

    await MemoStore.assign(category: 'Food', memo: await stored(memo), db: db);
    expect((await txn(id)).categoryOverride, 'Food');
    await MemoStore.assign(
        category: 'Shopping', memo: await stored(memo), db: db);
    expect((await txn(id)).categoryOverride, 'Shopping');
  });

  test('candidates go the same way, nearest first, exact amounts marked',
      () async {
    final memo = memoFor(at: ist(2026, 9, 22));
    await MemoStore.insert(memo, db: db);
    await ImportService.insertCapturedAlert(
        rowFor(reference: '100000000001', at: ist(2026, 9, 18)), db: db);
    await ImportService.insertCapturedAlert(
        rowFor(reference: '100000000002', at: ist(2026, 9, 23), amountPaise: 999),
        db: db);
    await ImportService.insertCapturedAlert(
        rowFor(
            reference: '100000000003',
            at: ist(2026, 9, 22),
            direction: Direction.credit),
        db: db);

    final candidates = Detections.candidates(await stored(memo),
        await db.select(db.storedTransactions).get(), const []);

    expect([for (final c in candidates) c.txn.reference],
        ['100000000002', '100000000001']);
    expect([for (final c in candidates) c.sameAmount], [false, true]);
  });

  test('completing a detection makes it a ledger row', () async {
    final memo = memoFor();
    await MemoStore.insert(memo, db: db);

    final id = await Detections.promote(await stored(memo),
        reference: ' 627775786529 ', db: db);

    final row = await txn(id);
    expect([row.reference, row.amountPaise, row.counterparty],
        ['627775786529', 45000, 'QWERTYSHOP']);
    expect((await stored(memo)).mergedTxnUuid, id);
  });

  test('a reference the ledger already has links to that row', () async {
    final existing =
        (await ImportService.insertCapturedAlert(rowFor(), db: db))!;
    final memo = memoFor();
    await MemoStore.insert(memo, db: db);

    final id = await Detections.promote(await stored(memo),
        reference: '627775786529', db: db);

    expect(id, existing);
    expect(await db.select(db.storedTransactions).get(), hasLength(1));
  });

  test("the agent's finds: with a reference a row, without one a detection",
      () async {
    final now = ist(2026, 11, 2);
    final found = [
      Detection(
          date: ist(2026, 11, 1),
          amountPaise: 34900,
          direction: Direction.debit,
          counterparty: 'Swiggy',
          reference: '630512398765'),
      Detection(
          date: ist(2026, 11, 1),
          amountPaise: 9900,
          direction: Direction.debit,
          counterparty: 'ZEPTO'),
    ];

    expect(await Detections.ingest(found, receivedAt: now, db: db),
        (added: 1, waiting: 1, known: 0));
    final open = Detections.open(await MemoStore.all(db));
    expect([for (final m in open) m.payee], ['ZEPTO']);

    expect(await Detections.ingest(found, receivedAt: now, db: db),
        (added: 0, waiting: 0, known: 2));
  });
}
