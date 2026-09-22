// The Android correction loop: a captured alert becomes a categorization, a
// categorization becomes a rule, and a rule reaches back over history.
//
// What is provable without a device is everything except delivery: the
// notification decision (`CaptureNotifier.plan`), the rule-offer arithmetic
// (`RuleImpact` over rows projected from REAL transactions), the queue a
// notification button leaves behind, the health indicator's two-timestamp
// reasoning, the import merge, and the standing guarantee that a memo is a
// label and never a ledger entry.
//
// What is NOT provable here, and is not faked: whether a banner is actually
// posted, whether its action buttons arrive back in Dart, and whether the
// notification listener keeps delivering after the app's process is killed
// (it does not — see `CaptureNotifier`'s header).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_notifier.dart';
import 'package:hisab/services/capture_prefs.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/services/queries.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab/widgets/needs_review_section.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime ist(int year, int month, int day, [int hour = 12, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

final ruleset = Ruleset.fromJsonString(
    File('assets/rulesets/india-default.json').readAsStringSync());

PendingMemo memoFor({
  int amountPaise = 45000,
  String payee = 'QWERTYSHOP',
  String? vpa,
  DateTime? at,
  String? note,
}) =>
    PendingMemo(
      amountPaise: amountPaise,
      direction: Direction.debit,
      payee: payee,
      vpa: vpa,
      accountTail: '1234',
      date: at ?? ist(2026, 9, 22),
      capturedAt: at ?? ist(2026, 9, 22),
      note: note,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => db.close());

  Future<String> insertTxn({
    required String counterparty,
    required String narration,
    int amountPaise = 45000,
    Direction direction = Direction.debit,
    Source source = Source.gpay,
    DateTime? date,
    String? categoryOverride,
  }) async {
    final uuid = newId();
    await db.into(db.storedTransactions).insert(
        StoredTransactionsCompanion.insert(
          uuid: uuid,
          contentHash: uuid,
          sourceRaw: source.rawValue,
          dateMs: (date ?? ist(2026, 9, 20)).toUtc().millisecondsSinceEpoch,
          amountPaise: amountPaise,
          direction: direction.name,
          counterparty: counterparty,
          narration: narration,
          documentId: 'doc',
          categoryOverride: Value(categoryOverride),
        ));
    return uuid;
  }

  Future<Map<String, String>> categories() async {
    final txns = await db.select(db.storedTransactions).get();
    final rules = await db.select(db.storedCategoryRules).get();
    final matches = await db.select(db.storedMatches).get();
    final matcher = Queries.matcher(rules);
    final selfTransfers = Queries.selfTransferUuids(txns);
    return {
      for (final txn in Queries.visible(txns, matches))
        txn.uuid: Queries.effectiveCategory(txn, matcher, selfTransfers)
    };
  }

  // MARK: - the correction loop

  group('assigning a category', () {
    test('a memo assigned a category leaves the pending list', () async {
      final memo = memoFor();
      expect(await MemoStore.insert(memo, db: db), isTrue);
      expect(await MemoStore.pending(db), hasLength(1));

      final stored = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      await MemoStore.assign(category: 'Shopping', memo: stored, db: db);

      expect(await MemoStore.pending(db), isEmpty);
      // Still THERE, just not pending: the memo is what stops the same alert
      // being captured again, and it carries the answer the user gave.
      final after = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      expect(after.assignedCategory, 'Shopping');
    });
  });

  group('the rule offer', () {
    test('the promised count equals the rows that actually change', () async {
      // Two rows with the SAME text. One is plain; the other the user
      // categorized by hand, which no rule may ever override.
      final plain = await insertTxn(
          counterparty: 'QWERTYSHOP', narration: 'UPI-QWERTYSHOP-9876');
      final overridden = await insertTxn(
          counterparty: 'QWERTYSHOP',
          narration: 'UPI-QWERTYSHOP-1111',
          categoryOverride: 'Travel');

      final before = await categories();
      expect(before[plain], Categorizer.uncategorized);
      expect(before[overridden], 'Travel');

      final txns = await db.select(db.storedTransactions).get();
      final matches = await db.select(db.storedMatches).get();
      final selfTransfers = Queries.selfTransferUuids(txns);
      final promised = RuleImpact.affectedCount(
        pattern: 'qwertyshop',
        category: 'Shopping',
        rows: Queries.impactRows(txns, matches, selfTransfers),
        rules: Queries.rules(await db.select(db.storedCategoryRules).get()),
      );
      expect(promised, 1, reason: 'the override-bearing row is not movable');

      await db.into(db.storedCategoryRules).insert(
          StoredCategoryRulesCompanion.insert(
              id: newId(),
              pattern: 'qwertyshop',
              category: 'Shopping',
              sortOrder: 0));

      final after = await categories();
      final changed = [
        for (final uuid in before.keys)
          if (before[uuid] != after[uuid]) uuid
      ];
      // The count is shown to the user as a promise — "this will also update
      // N past transactions" — so it is asserted against what really moved,
      // not merely against itself.
      expect(changed.length, promised);
      expect(after[plain], 'Shopping');
      expect(after[overridden], 'Travel',
          reason: 'a rule must never override an explicit choice');
    });

    test('a self transfer is never counted as movable', () async {
      // A debit in one bank paired with an equal credit in another, two days
      // apart: `Queries.effectiveCategory` labels both from reconciliation
      // BEFORE the matcher runs, so no rule can move them. If `impactRows`
      // left `isSelfTransfer` at a default the count would silently inflate,
      // which is the exact failure the flag exists to prevent.
      await insertTxn(
          counterparty: 'QWERTYSHOP',
          narration: 'IMPS-QWERTYSHOP',
          source: Source.hdfc,
          date: ist(2026, 9, 20));
      await insertTxn(
          counterparty: 'QWERTYSHOP',
          narration: 'IMPS-QWERTYSHOP',
          direction: Direction.credit,
          source: Source.idfc,
          date: ist(2026, 9, 21));

      final txns = await db.select(db.storedTransactions).get();
      final matches = await db.select(db.storedMatches).get();
      final selfTransfers = Queries.selfTransferUuids(txns);
      expect(selfTransfers, hasLength(2), reason: 'both sides are flagged');

      final rows = Queries.impactRows(txns, matches, selfTransfers);
      expect(rows.where((r) => r.isSelfTransfer), hasLength(2));
      expect(
          RuleImpact.affectedCount(
              pattern: 'qwertyshop',
              category: 'Shopping',
              rows: rows,
              rules: const []),
          0);
    });
  });

  // MARK: - the notification decision

  group('CaptureNotifier.plan', () {
    CaptureNotificationPlan? planFor({
      String payee = 'QWERTYSHOP',
      List<CategoryRule> rules = const [],
      List<SpendRecord> records = const [],
      DateTime? now,
      int sentToday = 0,
    }) =>
        CaptureNotifier.plan(
          memo: memoFor(payee: payee),
          rules: rules,
          records: records,
          ruleset: ruleset,
          now: now ?? ist(2026, 9, 22, 14, 30),
          sentToday: sentToday,
        );

    test('a payee Hisab already knows is never asked about', () {
      expect(
          planFor(payee: 'ZOMATO', rules: [
            const CategoryRule(
                id: 'r1', pattern: 'zomato', category: 'Food Delivery')
          ]),
          isNull,
          reason: 'the feature exists for the payees the rules do NOT cover');
    });

    test('an unknown payee gets three one-tap answers', () {
      final plan = planFor()!;
      expect(plan.captureHash, memoFor().captureHash);
      expect(plan.body, contains('QWERTYSHOP'));
      expect(plan.categories, hasLength(3));
      expect(plan.actionIds.first,
          '${CaptureNotifier.categoryActionPrefix}${plan.categories.first}');
      expect(plan.fireAt, isNull);
    });

    test('never more actions than Android will draw', () {
      // Android's standard template renders at most three actions and drops
      // the rest WITHOUT SAYING SO — observed on an API 36 emulator, where a
      // fourth action ("Later", as iOS has it) simply was not there. The cap
      // is applied in Dart so it is visible and assertable rather than a
      // silent platform truncation.
      //
      // Built by hand rather than from `plan`, which asks `CategoryRanker`
      // for three: measuring the cap against a list that already obeys it
      // proves nothing, and the assertion would still pass with the cap
      // deleted.
      const plan = CaptureNotificationPlan(
        captureHash: 'abc123',
        title: 'What was this?',
        body: '₹450.00 to QWERTYSHOP',
        categories: ['Food', 'Travel', 'Shopping', 'Bills', 'Rent'],
      );
      expect(plan.actionIds, hasLength(CaptureNotifier.maxActions));
      expect(plan.actionIds, [
        '${CaptureNotifier.categoryActionPrefix}Food',
        '${CaptureNotifier.categoryActionPrefix}Travel',
        '${CaptureNotifier.categoryActionPrefix}Shopping',
      ], reason: 'the first three, in order — not an arbitrary three');
    });

    test('the daily cap suppresses rather than queues', () {
      expect(planFor(sentToday: NotificationPolicy.dailyCap), isNull);
    });

    test('quiet hours hold until the morning', () {
      final plan = planFor(now: ist(2026, 9, 22, 23, 10))!;
      expect(plan.fireAt, ist(2026, 9, 23, 8, 0));
    });
  });

  group('action ids', () {
    test('a category containing the separator survives a round trip', () {
      const category = 'Rent | Utilities';
      final id = '${CaptureNotifier.categoryActionPrefix}$category';
      expect(CaptureNotifier.categoryFromActionId(id), category,
          reason: 'splitting on "|" would silently assign "Rent "');
    });

    test('Later and a bare tap carry no category', () {
      expect(CaptureNotifier.categoryFromActionId(CaptureNotifier.laterActionId),
          isNull);
      expect(CaptureNotifier.categoryFromActionId(null), isNull);
      expect(CaptureNotifier.categoryFromActionId('CAT|'), isNull);
    });

    test('two memos get two notification ids', () {
      // The property the feature rests on. Android replaces a notification
      // that reuses an id, so a shared id would mean the second unknown payee
      // of the afternoon silently wiping the banner asking about the first.
      final ids = {
        for (final payee in const ['QWERTYSHOP', 'CHAIWALA JUNCTION', 'ZOMATO'])
          CaptureNotifier.notificationId(memoFor(payee: payee).captureHash)
      };
      expect(ids, hasLength(3),
          reason: 'a shared id means one banner replaces another');
      for (final id in ids) {
        // Android notification ids are ints; a negative one is legal but the
        // hash is masked to 31 bits, so this also pins the mask.
        expect(id, greaterThanOrEqualTo(0));
      }
    });

    test('the same memo keeps its notification id', () {
      // The other half: a re-posted alert must replace its OWN banner rather
      // than stack a second copy.
      expect(CaptureNotifier.notificationId(memoFor().captureHash),
          CaptureNotifier.notificationId(memoFor().captureHash));
    });
  });

  // MARK: - what a notification button leaves behind

  group('queued rule offers', () {
    test('a category button assigns and queues an offer', () async {
      await CapturePrefs.setEnabled(true);
      final memo = memoFor();
      await MemoStore.insert(memo, db: db);

      await CaptureNotifier.respond(
          actionId: '${CaptureNotifier.categoryActionPrefix}Shopping',
          captureHash: memo.captureHash,
          db: db);

      expect((await MemoStore.find(hash: memo.captureHash, db: db))!
          .assignedCategory, 'Shopping');
      expect(await CaptureNotifier.pendingRuleOffers(),
          [RuleOffer(captureHash: memo.captureHash, category: 'Shopping')]);
    });

    test('with capture off a delivered banner is inert', () async {
      final memo = memoFor();
      await MemoStore.insert(memo, db: db);
      // The toggle is off; the banner was delivered before it moved.
      await CaptureNotifier.respond(
          actionId: '${CaptureNotifier.categoryActionPrefix}Shopping',
          captureHash: memo.captureHash,
          db: db);

      expect((await MemoStore.find(hash: memo.captureHash, db: db))!
          .assignedCategory, isNull);
      expect(await CaptureNotifier.pendingRuleOffers(), isEmpty);
    });

    test('two taps on one memo leave only the last answer', () async {
      await CaptureNotifier.queueOffer(
          const RuleOffer(captureHash: 'h1', category: 'Shopping'));
      await CaptureNotifier.queueOffer(
          const RuleOffer(captureHash: 'h2', category: 'Travel'));
      await CaptureNotifier.queueOffer(
          const RuleOffer(captureHash: 'h1', category: 'Groceries'));

      expect(await CaptureNotifier.pendingRuleOffers(), [
        const RuleOffer(captureHash: 'h2', category: 'Travel'),
        const RuleOffer(captureHash: 'h1', category: 'Groceries'),
      ]);

      await CaptureNotifier.clearOffer('h2');
      expect(await CaptureNotifier.pendingRuleOffers(),
          [const RuleOffer(captureHash: 'h1', category: 'Groceries')]);
    });

    test('an erase collects the queued offer', () async {
      // `CapturePrefs.clearCapturedData` was written as a prefix sweep in
      // anticipation of exactly this key, which names a payee's capture hash
      // and the category the user chose for it. This is the test that the
      // anticipation paid off.
      await CaptureNotifier.queueOffer(
          const RuleOffer(captureHash: 'h1', category: 'Shopping'));
      await CapturePrefs.setEnabled(true);

      await CapturePrefs.clearCapturedData();

      expect(await CaptureNotifier.pendingRuleOffers(), isEmpty);
      expect(await CapturePrefs.isEnabled(), isTrue,
          reason: 'the toggle is a device setting the user chose, not '
              'something Hisab learned about their spending');
    });
  });

  // MARK: - health

  group('CaptureHealth', () {
    final now = ist(2026, 9, 22, 14, 0);

    CaptureHealth evaluate(
            {bool enabled = true, DateTime? attempt, DateTime? capture}) =>
        CaptureHealth.evaluate(
            enabled: enabled,
            lastAttemptAt: attempt,
            lastCaptureAt: capture,
            now: now);

    test('capture off is not a warning', () {
      expect(evaluate(enabled: false).state, CaptureHealthState.off);
      expect(evaluate(enabled: false).message, isNull);
    });

    test('nothing has ever arrived', () {
      final health = evaluate();
      expect(health.state, CaptureHealthState.neverArrived);
      expect(health.offersSetup, isTrue);
      expect(health.message, contains('cannot switch it on for you'));
    });

    test('a stale ATTEMPT means the listener may have stopped', () {
      final health = evaluate(
          attempt: ist(2026, 9, 18), capture: ist(2026, 9, 18));
      expect(health.state, CaptureHealthState.noAlerts);
      expect(health.days, 4);
      expect(health.offersSetup, isTrue);
      // The Android-specific half of the honesty: the most likely cause is
      // not a setting the user got wrong, it is the process having been
      // killed, and the copy says so.
      expect(health.message, contains('force-stopped'));
    });

    test('alerts arriving that will not parse is a DIFFERENT state', () {
      // Attempt recent, capture stale. Their setup is fine and sending them
      // to the setup screen would be a lie — the whole reason two timestamps
      // exist rather than one.
      final health =
          evaluate(attempt: ist(2026, 9, 22), capture: ist(2026, 9, 17));
      expect(health.state, CaptureHealthState.unreadable);
      expect(health.offersSetup, isFalse);
      expect(health.message, contains('could not read them'));
    });

    test('an attempt with no capture at all is also unreadable', () {
      final health = evaluate(attempt: ist(2026, 9, 22));
      expect(health.state, CaptureHealthState.unreadable);
      expect(health.offersSetup, isFalse);
    });

    test('three days of quiet is ordinary, four is not', () {
      expect(
          evaluate(attempt: ist(2026, 9, 19), capture: ist(2026, 9, 19)).state,
          CaptureHealthState.healthy);
      expect(
          evaluate(attempt: ist(2026, 9, 18), capture: ist(2026, 9, 18)).state,
          CaptureHealthState.noAlerts);
    });

    test('a longer silence is a DIFFERENT value, not the same one', () {
      // The banner keeps the health it last read and replaces it only when
      // the new reading differs, so what "differs" means is what decides
      // whether "No alerts received in 4 days" ever becomes 9. Comparing the
      // state alone froze the count at whatever it was when the dashboard
      // was first shown.
      final four =
          evaluate(attempt: ist(2026, 9, 18), capture: ist(2026, 9, 18));
      final nine =
          evaluate(attempt: ist(2026, 9, 13), capture: ist(2026, 9, 13));
      expect(four.state, nine.state);
      expect(four, isNot(nine));
      expect(nine.message, contains('9 days'));
    });

    test('it reads the prefs the capture pipeline writes', () async {
      await CapturePrefs.setEnabled(true);
      await CapturePrefs.setLastAttemptAt(now);
      await CapturePrefs.setLastCaptureAt(now);
      expect((await CaptureHealth.current(now: now)).state,
          CaptureHealthState.healthy);
    });
  });

  // MARK: - the import merge

  group('import', () {
    ImportService service() => ImportService(
        db: db,
        resolver: ImportResolver(
            registry: liveRegistry(), specs: SpecStore.parseAll(const [])));

    Future<void> importOne({
      required String counterparty,
      required String narration,
      int amountPaise = 45000,
      DateTime? date,
    }) async {
      final at = date ?? ist(2026, 9, 22);
      await service().insertParsedDocument(
        parsed: ParsedDocument(
          source: Source.hdfc,
          declaredPeriod: DatePeriod(ist(2026, 9, 1), ist(2026, 9, 30)),
          transactions: [
            ParsedTransaction(
              date: at,
              amountPaise: amountPaise,
              direction: Direction.debit,
              counterparty: counterparty,
              reference: null,
              narration: narration,
            )
          ],
        ),
        source: Source.hdfc,
        filename: 'statement.csv',
        fileHash: newId(),
      );
    }

    test('an import retires the memo it matches and keeps its note',
        () async {
      final memo = memoFor(
          payee: 'QWERTYSHOP', at: ist(2026, 9, 22), note: 'birthday gift');
      await MemoStore.insert(memo, db: db);

      await importOne(
          counterparty: 'QWERTYSHOP', narration: 'UPI-QWERTYSHOP-9876');

      final stored = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      expect(stored.mergedTxnUuid, isNotNull);
      expect(await MemoStore.pending(db), isEmpty,
          reason: 'a retired memo is no longer waiting for an answer');
      // NOT transferred onto the transaction: neither core has a note column
      // on a transaction (see ImportService._retireMemos). The note is kept
      // on the memo, which now points at the row it belongs to.
      expect(stored.note, 'birthday gift');
      final txns = await db.select(db.storedTransactions).get();
      expect(txns.single.uuid, stored.mergedTxnUuid);
    });

    test('an import does not claim an unrelated memo', () async {
      final memo = memoFor(payee: 'QWERTYSHOP', amountPaise: 12345);
      await MemoStore.insert(memo, db: db);

      await importOne(
          counterparty: 'SOMEONE ELSE', narration: 'UPI-SOMEONE-ELSE');

      final stored = (await MemoStore.find(hash: memo.captureHash, db: db))!;
      expect(stored.mergedTxnUuid, isNull);
      expect(await MemoStore.pending(db), hasLength(1));
    });

    test('a later import cannot re-claim a transaction a memo already took',
        () async {
      // `MemoMerger.merge` guarantees each candidate is used at most once
      // WITHIN one call. A row claimed on an earlier import is attached to a
      // memo that is no longer among the unmerged ones, so offering the whole
      // table again would let a second memo claim the same transaction and
      // two memos would point at one payment. Candidates are therefore the
      // rows THIS import inserted, matching the Swift twin.
      final first = memoFor(payee: 'QWERTYSHOP', at: ist(2026, 9, 22));
      await MemoStore.insert(first, db: db);
      await importOne(
          counterparty: 'QWERTYSHOP',
          narration: 'UPI-QWERTYSHOP-9876',
          date: ist(2026, 9, 22));
      final claimed =
          (await MemoStore.find(hash: first.captureHash, db: db))!.mergedTxnUuid;
      expect(claimed, isNotNull);

      // A second memo that WOULD match that row: same amount, same payee,
      // one day earlier, well inside the three-day window.
      final second = memoFor(payee: 'QWERTYSHOP', at: ist(2026, 9, 21));
      await MemoStore.insert(second, db: db);
      await importOne(
          counterparty: 'SOMEONE ELSE',
          narration: 'UPI-SOMEONE-ELSE',
          amountPaise: 11100,
          date: ist(2026, 9, 25));

      expect(
          (await MemoStore.find(hash: second.captureHash, db: db))!
              .mergedTxnUuid,
          isNull,
          reason: 'the earlier import\'s row is not on offer again');
    });

    test('a memo changes no analytics total', () async {
      // Memos are a labelling channel. If one moves a number, the ledger's
      // integrity guarantee is gone — a memo has no UTR, so it can join
      // neither content-hash dedup nor balance-chain validation.
      await importOne(
          counterparty: 'SOMEONE ELSE',
          narration: 'UPI-SOMEONE-ELSE',
          amountPaise: 10000);

      Future<int> spend() async {
        final txns = await db.select(db.storedTransactions).get();
        final matches = await db.select(db.storedMatches).get();
        final rules = await db.select(db.storedCategoryRules).get();
        return Analytics.monthStats(
                Queries.analytics(txns, matches, Queries.matcher(rules)),
                YearMonth(2026, 9))
            .spendPaise;
      }

      final before = await spend();
      expect(before, 10000);

      for (final payee in ['ALPHA', 'BETA', 'GAMMA']) {
        await MemoStore.insert(
            memoFor(payee: payee, amountPaise: 999900), db: db);
      }
      expect(await MemoStore.pending(db), hasLength(3));
      expect(await spend(), before);
    });
  });
}
