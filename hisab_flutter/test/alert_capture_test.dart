// Capture through the on-device extractor: `NotificationCapture.handle` with
// an extractor turns one alert into a memo, a ledger row, both, or nothing
// (AlertCapture), and the ledger row is dedup'd, reconciled, kept out of
// coverage and recognised as a self transfer like a statement row.
//
// The extractor is faked — it hands back the ExtractedAlert scripted for the
// text — so no ONNX Runtime is needed; AlertCapture itself is pinned by
// alert-capture.json in hisab_core.
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_prefs.dart';
import 'package:hisab/services/demo_data.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/services/notification_capture.dart';
import 'package:hisab/services/queries.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime ist(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

const smsPackage = 'com.google.android.apps.messaging';
final allowlist = CaptureAllowlist(version: 1, packages: const {smsPackage});

/// Stands in for the ONNX model: the alert scripted for a notification's
/// content, or "not a transaction" for anything unscripted.
class FakeExtractor implements AlertExtractor {
  final Map<String, ExtractedAlert> alerts;
  final bool fails;
  FakeExtractor(this.alerts, {this.fails = false});

  @override
  Future<ExtractedAlert> extract(String text) async {
    if (fails) throw StateError('model unavailable');
    for (final entry in alerts.entries) {
      if (text.endsWith(entry.key)) return entry.value;
    }
    return const ExtractedAlert.notTransaction(0.98);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Notification contents. The fake reads only these keys, never their words.
const upiDebit = 'UPI debit to Munchmart';
const impsDebit = 'IMPS debit from 816';
const impsCredit = 'IMPS credit to 293';
const noRefDebit = 'Card spend at Swiggy';
const promo = 'Get a pre-approved loan today';

final extractor = FakeExtractor({
  upiDebit: const ExtractedAlert(
    isTransaction: true,
    direction: Direction.debit,
    amountPaise: 23900,
    ref: '627775786529',
    payee: 'MUNCHMART TECHNOLOGIES PR',
    ownAccountTail: '3293',
    dateIso: '2026-10-04',
    classConfidence: 0.99,
  ),
  // One IMPS transfer between the user's own accounts, alerted by both banks.
  impsDebit: const ExtractedAlert(
    isTransaction: true,
    direction: Direction.debit,
    amountPaise: 3000000,
    ref: '626523840940',
    ownAccountTail: '816',
    counterpartyAccountTail: '293',
    dateIso: '2026-09-22',
    classConfidence: 0.99,
  ),
  impsCredit: const ExtractedAlert(
    isTransaction: true,
    direction: Direction.credit,
    amountPaise: 3000000,
    ref: '626523840940',
    ownAccountTail: '293',
    counterpartyAccountTail: '816',
    dateIso: '2026-09-22',
    classConfidence: 0.99,
  ),
  noRefDebit: const ExtractedAlert(
    isTransaction: true,
    direction: Direction.debit,
    amountPaise: 45000,
    payee: 'SWIGGY',
    ownAccountTail: '1234',
    dateIso: '2026-10-03',
    classConfidence: 0.99,
  ),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<int> notified;
  final now = ist(2026, 10, 4, 18, 30);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    await CapturePrefs.setEnabled(true);
    notified = [];
  });
  tearDown(() async => db.close());

  Future<CaptureOutcome> handle(String content,
          {DateTime? at, AlertExtractor? using}) =>
      NotificationCapture.handle(
        packageName: smsPackage,
        title: 'Bank',
        content: content,
        hasRemoved: false,
        db: db,
        allowlist: allowlist,
        now: at ?? now,
        extractor: using ?? extractor,
        onCaptured: (memo) async => notified.add(memo.amountPaise),
      );

  Future<List<StoredTransaction>> alertRows() async => [
        for (final txn in await db.select(db.storedTransactions).get())
          if (txn.sourceRaw == 'alert') txn
      ];

  Future<List<StoredDocument>> alertDocs() async => [
        for (final doc in await db.select(db.storedDocuments).get())
          if (doc.sourceRaw == 'alert') doc
      ];

  /// The dashboard's numbers for [month], through the app's projections.
  Future<MonthStats> stats(YearMonth month) async {
    final txns = await db.select(db.storedTransactions).get();
    final matches = await db.select(db.storedMatches).get();
    return Analytics.monthStats(
        Queries.analytics(txns, matches, Queries.matcher(const [])), month);
  }

  /// One row of an already-imported HDFC statement.
  Future<void> statementRow(
      {required int paise, required DateTime date, String? ref}) async {
    await db.into(db.storedDocuments).insert(
        StoredDocumentsCompanion.insert(
          id: 'stmt',
          sourceRaw: 'hdfc',
          filename: 'hdfc.xls',
          fileSha256: 'stmt-sha',
          periodStartMs: ist(2026, 9, 1).millisecondsSinceEpoch,
          periodEndMs: ist(2026, 10, 31).millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore);
    final txn = ParsedTransaction(
        date: date,
        amountPaise: paise,
        direction: Direction.debit,
        counterparty: 'UPI-SHOP',
        reference: ref,
        narration: 'UPI-SHOP');
    await db.into(db.storedTransactions).insert(
        StoredTransactionsCompanion.insert(
          uuid: newId(),
          contentHash: txn.contentHash(Source.hdfc),
          sourceRaw: 'hdfc',
          dateMs: date.millisecondsSinceEpoch,
          amountPaise: paise,
          direction: 'debit',
          counterparty: txn.counterparty,
          reference: Value(ref),
          narration: txn.narration,
          documentId: 'stmt',
        ));
  }

  final october = YearMonth(2026, 10);
  final september = YearMonth(2026, 9);

  test('(a) an alert with a reference: a memo, one ledger row, and the month '
      'total rises by its amount', () async {
    await statementRow(paise: 10000, date: ist(2026, 10, 2));
    expect((await stats(october)).spendPaise, 10000);

    expect(await handle(upiDebit), CaptureOutcome.captured);

    final memos = await MemoStore.all(db);
    expect(memos, hasLength(1));
    expect(memos.single.payee, 'MUNCHMART TECHNOLOGIES PR');

    final row = (await alertRows()).single;
    expect(row.amountPaise, 23900);
    expect(row.direction, 'debit');
    expect(row.reference, '627775786529');
    expect(row.counterparty, 'MUNCHMART TECHNOLOGIES PR');
    expect(row.dateMs, ist(2026, 10, 4).millisecondsSinceEpoch);

    final doc = (await alertDocs()).single;
    expect(doc.filename, 'Captured alerts');
    expect(doc.fileSha256, ImportService.capturedAlertsFileHash);
    expect(row.documentId, doc.id);

    expect((await stats(october)).spendPaise, 33900);
    expect(notified, [23900]);
    expect(await CapturePrefs.lastCaptureAt(), now);
  });

  test('(b) the same alert again adds nothing', () async {
    await statementRow(paise: 10000, date: ist(2026, 10, 2));
    await handle(upiDebit);
    final later = ist(2026, 10, 4, 20, 0);

    expect(await handle(upiDebit, at: later), CaptureOutcome.duplicate);

    expect(await MemoStore.all(db), hasLength(1));
    expect(await alertRows(), hasLength(1));
    expect(await alertDocs(), hasLength(1));
    expect((await stats(october)).spendPaise, 33900);
    expect(notified, [23900], reason: 'no second banner for a re-post');
    expect(await CapturePrefs.lastCaptureAt(), later);
  });

  test('(c) both legs of an IMPS self transfer: two rows, totals unchanged',
      () async {
    await statementRow(paise: 10000, date: ist(2026, 9, 10));
    final before = await stats(september);
    expect(before.spendPaise, 10000);
    expect(before.incomePaise, 0);

    expect(await handle(impsDebit), CaptureOutcome.captured);
    expect(await handle(impsCredit), CaptureOutcome.captured);

    final rows = await alertRows();
    expect(rows, hasLength(2));
    expect({for (final r in rows) r.direction}, {'debit', 'credit'});
    expect(await MemoStore.all(db), isEmpty,
        reason: 'an account number is nobody to label');
    expect(notified, isEmpty);
    expect(await CapturePrefs.lastCaptureAt(), now,
        reason: 'a ledger-only capture is still a capture');

    final after = await stats(september);
    expect(after.spendPaise, 10000);
    expect(after.incomePaise, 0);

    final txns = await db.select(db.storedTransactions).get();
    final self = Queries.selfTransferUuids(txns);
    final matcher = Queries.matcher(const []);
    for (final row in rows) {
      expect(self, contains(row.uuid));
      expect(Queries.effectiveCategory(row, matcher, self),
          Categorizer.selfTransfer);
    }
  });

  test('(d) an alert without a reference stays a memo', () async {
    expect(await handle(noRefDebit), CaptureOutcome.captured);

    expect((await MemoStore.all(db)).single.payee, 'SWIGGY');
    expect(await alertRows(), isEmpty);
    expect(await alertDocs(), isEmpty);
    expect((await stats(october)).spendPaise, 0);
    expect(notified, [45000]);
  });

  test('(e) a non-transaction stores nothing', () async {
    expect(await handle(promo), CaptureOutcome.unparsed);

    expect(await MemoStore.all(db), isEmpty);
    expect(await db.select(db.storedTransactions).get(), isEmpty);
    expect(await db.select(db.storedDocuments).get(), isEmpty);
    expect(await CapturePrefs.lastAttemptAt(), now);
    expect(await CapturePrefs.lastCaptureAt(), isNull);
  });

  test('a failing extractor falls back to the parser', () async {
    const body = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA '
        'vedant@okaxis. Ref 123456789012.';
    expect(await handle(body, using: FakeExtractor({}, fails: true)),
        CaptureOutcome.captured);

    expect((await MemoStore.all(db)).single.payee, 'vedant@okaxis');
    expect(await alertRows(), isEmpty,
        reason: 'the parser path files memos only, as before the extractor');
  });

  test('a statement row with the same reference confirms the alert row',
      () async {
    await statementRow(
        paise: 23900, date: ist(2026, 10, 4), ref: '627775786529');

    await handle(upiDebit);

    final matches = await db.select(db.storedMatches).get();
    expect(matches.single.tier, 'reference');
    expect(matches.single.appUuid, (await alertRows()).single.uuid);
    expect((await stats(october)).spendPaise, 23900,
        reason: 'one payment, counted once');
  });

  test('one "Captured alerts" document, widened to cover its rows and kept '
      'out of coverage', () async {
    await statementRow(paise: 10000, date: ist(2026, 10, 2));
    await handle(upiDebit);
    await handle(impsDebit);

    final doc = (await alertDocs()).single;
    expect(doc.periodStartMs, ist(2026, 9, 22).millisecondsSinceEpoch);
    expect(doc.periodEndMs, ist(2026, 10, 4).millisecondsSinceEpoch);
    expect({for (final r in await alertRows()) r.documentId}, {doc.id});

    final documents = await db.select(db.storedDocuments).get();
    final grid = Queries.grid(Queries.statements(documents), const []);
    expect(grid.sources, [Source.hdfc]);
    expect(Queries.insightPeriods(Queries.statements(documents)), hasLength(1));
  });

  /// A GPay export holding the (a) payment: same reference and direction.
  Future<ImportReport> importGpay() => ImportService(
          db: db,
          resolver: ImportResolver(registry: liveRegistry(), specs: const []))
      .insertParsedDocument(
        parsed: ParsedDocument(
          source: Source.gpay,
          declaredPeriod: null,
          transactions: [
            ParsedTransaction(
                date: ist(2026, 10, 4, 18, 29),
                amountPaise: 23900,
                direction: Direction.debit,
                counterparty: 'Munchmart',
                reference: '627775786529',
                narration: 'Paid to Munchmart'),
          ],
        ),
        source: Source.gpay,
        filename: 'gpay.html',
        fileHash: 'gpay-sha',
      );

  Future<List<StoredTransaction>> gpayRows() async => [
        for (final txn in await db.select(db.storedTransactions).get())
          if (txn.sourceRaw == 'gpay') txn
      ];

  test('(f) capture, then the app export for the same payment: the export '
      'replaces the alert row and the payment is counted once', () async {
    await statementRow(paise: 10000, date: ist(2026, 10, 2));
    await handle(upiDebit);
    expect(await alertRows(), hasLength(1));
    expect((await stats(october)).spendPaise, 33900);

    final report = await importGpay();

    expect(report.newCount, 1);
    expect(await alertRows(), isEmpty);
    expect(await gpayRows(), hasLength(1));
    expect((await stats(october)).spendPaise, 33900,
        reason: 'one payment, counted once');
    expect(await MemoStore.all(db), hasLength(1),
        reason: 'the memo is untouched');
  });

  test('(g) the app export first, then the capture: no alert row', () async {
    await statementRow(paise: 10000, date: ist(2026, 10, 2));
    await importGpay();
    expect((await stats(october)).spendPaise, 33900);

    expect(await handle(upiDebit), CaptureOutcome.captured,
        reason: 'the memo is still new');

    expect(await alertRows(), isEmpty);
    expect(await gpayRows(), hasLength(1));
    expect(await MemoStore.all(db), hasLength(1));
    expect((await stats(october)).spendPaise, 33900);
  });

  test('erase all removes alert rows and their document', () async {
    await handle(upiDebit);
    expect(await alertRows(), hasLength(1));

    await DemoData.eraseAll(db);

    expect(await db.select(db.storedTransactions).get(), isEmpty);
    expect(await db.select(db.storedDocuments).get(), isEmpty);
    expect(await MemoStore.all(db), isEmpty);
  });
}
