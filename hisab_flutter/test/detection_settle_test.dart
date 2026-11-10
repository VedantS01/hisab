// Detections meeting each other and the ledger: Vedant's merge rules
// (amount, account tail, time, counterparty; union with the bank winning)
// as the app applies them when a detection lands or is corrected.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/detections.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/state.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';

DateTime ist(int year, int month, int day, [int hour = 12, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

PendingMemo memo({
  int amountPaise = 45000,
  String payee = '',
  String? vpa,
  String? tail,
  DateTime? at,
  DateTime? captured,
  Direction direction = Direction.debit,
}) =>
    PendingMemo(
      amountPaise: amountPaise,
      direction: direction,
      payee: payee,
      vpa: vpa,
      accountTail: tail,
      date: at ?? ist(2026, 9, 22),
      capturedAt: captured ?? at ?? ist(2026, 9, 22),
    );

ParsedTransaction row({
  int amountPaise = 45000,
  String reference = '627775786529',
  String counterparty = 'QWERTYSHOP',
  String narration = '',
  DateTime? at,
}) =>
    ParsedTransaction(
      date: at ?? ist(2026, 9, 22),
      amountPaise: amountPaise,
      direction: Direction.debit,
      counterparty: counterparty,
      reference: reference,
      narration: narration,
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<StoredPendingMemo> stored(PendingMemo m) async =>
      (await MemoStore.find(hash: m.captureHash, db: db))!;

  Future<Snapshot> snapshot() async => Snapshot(
        await db.select(db.storedTransactions).get(),
        await db.select(db.storedMatches).get(),
        const [],
        const [],
        const [],
        await db.select(db.storedPendingMemos).get(),
        await db.select(db.rejectedLinks).get(),
      );

  test('a second sighting of the same payment folds into the first; the union keeps both details',
      () async {
    final sms = memo(payee: 'Ram', tail: '1234', at: ist(2026, 9, 22, 9));
    final email = memo(
        payee: 'Ram Kumar', vpa: 'ram@okhdfc', tail: 'XX1234', at: ist(2026, 9, 22, 9, 4));
    await MemoStore.insert(sms, db: db);
    await Detections.settle(sms.captureHash, db: db);
    await MemoStore.insert(email, db: db);
    await Detections.settle(email.captureHash, db: db);

    final kept = await stored(sms);
    final folded = await stored(email);
    expect(kept.mergedTxnUuid, isNull);
    expect(kept.payee, 'Ram', reason: 'the earlier sighting wins a conflict');
    expect(kept.vpa, 'ram@okhdfc', reason: 'a field the earlier one lacked is filled');
    expect(folded.mergedTxnUuid, '${Detections.intoPrefix}${sms.captureHash}');
    expect(Detections.open(await MemoStore.all(db)).map((m) => m.captureHash),
        [sms.captureHash]);
  });

  test('a category given to the folded sighting lands on the detection the user sees',
      () async {
    final sms = memo(payee: 'Ram', tail: '1234', at: ist(2026, 9, 22, 9));
    final email = memo(
        payee: 'Ram Kumar', vpa: 'ram@okhdfc', tail: 'XX1234', at: ist(2026, 9, 22, 9, 4));
    await MemoStore.insert(sms, db: db);
    await Detections.settle(sms.captureHash, db: db);
    await MemoStore.insert(email, db: db);
    await Detections.settle(email.captureHash, db: db);

    await MemoStore.assign(category: 'Food', memo: await stored(email), db: db);

    expect((await stored(sms)).assignedCategory, 'Food');
  });

  test('different account tails never fold, same payee a day apart or not', () async {
    // A day apart so the two are distinct captures (the capture hash is by
    // day); the payee alone would merge them, the tails forbid it.
    final a = memo(payee: 'Ram', tail: '1234');
    final b = memo(payee: 'Ram', tail: '9876', at: ist(2026, 9, 23, 13));
    await MemoStore.insert(a, db: db);
    await MemoStore.insert(b, db: db);
    await Detections.settle(b.captureHash, db: db);
    expect(Detections.open(await MemoStore.all(db)), hasLength(2));
  });

  test('a detection links itself to the one row it is; the row keeps its own details',
      () async {
    final id = (await ImportService.insertCapturedAlert(
        row(counterparty: 'BLUE TOKAI COFFEE', narration: 'UPI/BLUE TOKAI/PAY'),
        db: db))!;
    final seen = memo(payee: 'Blue Tokai', at: ist(2026, 9, 23));
    await MemoStore.insert(seen, db: db);
    await Detections.settle(seen.captureHash, db: db);
    expect((await stored(seen)).mergedTxnUuid, id);
    final txn = await (db.select(db.storedTransactions)
          ..where((t) => t.uuid.equals(id)))
        .getSingle();
    expect(txn.counterparty, 'BLUE TOKAI COFFEE');
  });

  test('two rows equally likely: nothing links, both are suggested; a rejected one is not offered again',
      () async {
    final first = (await ImportService.insertCapturedAlert(
        row(reference: 'AAA111', counterparty: 'BLUE TOKAI', narration: 'UPI/BLUE TOKAI/1'),
        db: db))!;
    final second = (await ImportService.insertCapturedAlert(
        row(reference: 'BBB222', counterparty: 'BLUE TOKAI', narration: 'UPI/BLUE TOKAI/2'),
        db: db))!;
    final seen = memo(payee: 'Blue Tokai');
    await MemoStore.insert(seen, db: db);
    await Detections.settle(seen.captureHash, db: db);
    final open = await stored(seen);
    expect(open.mergedTxnUuid, isNull);
    expect(Detections.suggestions(open, await snapshot()).map((s) => s.$1.uuid),
        unorderedEquals([first, second]));

    await Detections.reject(seen.captureHash, first, db: db);
    expect(Detections.suggestions(open, await snapshot()).map((s) => s.$1.uuid), [second]);
    await Detections.settle(seen.captureHash, db: db);
    expect((await stored(seen)).mergedTxnUuid, second,
        reason: 'with the other turned down, one row is left and it takes the detection');
  });

  test('amount and time alone only suggest, never link', () async {
    final id = (await ImportService.insertCapturedAlert(
        row(counterparty: 'SOMEONE ELSE', narration: 'NEFT/XYZ'),
        db: db))!;
    final seen = memo(payee: 'Blue Tokai');
    await MemoStore.insert(seen, db: db);
    await Detections.settle(seen.captureHash, db: db);
    final open = await stored(seen);
    expect(open.mergedTxnUuid, isNull);
    final suggested = Detections.suggestions(open, await snapshot());
    expect(suggested.single.$1.uuid, id);
    expect(suggested.single.$2, MatchVerdict.suggested);
  });

  test('a correction is kept and matched again', () async {
    final id = (await ImportService.insertCapturedAlert(
        row(amountPaise: 45500, counterparty: 'BLUE TOKAI', narration: 'UPI/BLUE TOKAI'),
        db: db))!;
    final seen = memo(payee: 'Blue Tokai', amountPaise: 45000);
    await MemoStore.insert(seen, db: db);
    await Detections.settle(seen.captureHash, db: db);
    expect((await stored(seen)).mergedTxnUuid, isNull, reason: 'amounts differ');

    await Detections.edit(await stored(seen), amountPaise: 45500, accountTail: '4321', db: db);
    final after = await stored(seen);
    expect(after.amountPaise, 45500);
    expect(after.accountTail, '4321');
    expect(after.mergedTxnUuid, id);
  });
}
