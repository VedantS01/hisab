// What `main.dart` does with a notification response.
//
// `CaptureNotifier.respond` decides WHERE a tap should land by writing to
// `CaptureRouter`; `RootTabs` is the only thing that reads it. That read was
// untested, and it was broken: the launch-time response is replayed from
// `main` BEFORE `runApp`, so by the time `RootTabs.initState` calls
// `addListener` the value is already sitting in the notifier — and a
// `ValueNotifier` does not notify a listener about a value it already holds.
// A cold-launch tap therefore opened the dashboard and nothing else, which on
// Android is the COMMON case, because the capture listener has no background
// isolate and Hisab is usually not running when the alert arrives.
//
// These tests drive the widget, not a helper: the bug lived in the wiring.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/main.dart';
import 'package:hisab/services/capture_notifier.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/state.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab/widgets/memo_review_sheet.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ruleset = Ruleset.fromJsonString(
    File('assets/rulesets/india-default.json').readAsStringSync());
final insightsConfig = InsightsConfig.fromJsonString(
    File('assets/insights/insights-config.json').readAsStringSync());

PendingMemo memoFor(String payee) => PendingMemo(
      amountPaise: 45000,
      direction: Direction.debit,
      payee: payee,
      accountTail: '1234',
      date: DateTime.utc(2026, 9, 22, 6, 30),
      capturedAt: DateTime.utc(2026, 9, 22, 6, 30),
    );

void main() {
  late AppDatabase db;
  late AppState state;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    // Static, and therefore shared between tests in this file.
    CaptureRouter.reviewRequest.value = null;
    state = AppState(
      db: db,
      importService: ImportService(
        db: db,
        // No PDF parsers and no format specs: nothing here imports anything.
        resolver: ImportResolver(
            registry: liveRegistry(), specs: SpecStore.parseAll(const [])),
      ),
      ruleset: ruleset,
      insightsConfig: insightsConfig,
    );
  });

  tearDown(() async {
    CaptureRouter.reviewRequest.value = null;
    await db.close();
  });

  /// The payee AS THE OPEN SHEET SHOWS IT. The dashboard's needs-review card
  /// lists the same payees, so a bare `find.text` cannot tell "the sheet is
  /// open on this memo" from "this memo is in the list behind it".
  Finder inSheet(String text) => find.descendant(
      of: find.byType(MemoReviewContent), matching: find.text(text));

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(AppScope(
      state: state,
      child: const MaterialApp(home: RootTabs()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a tap that launched the app opens the memo', (tester) async {
    final memo = memoFor('CHAIWALA JUNCTION');
    await MemoStore.insert(memo, db: db);
    // Exactly what `CaptureNotifier.init`'s launch replay does, from `main`,
    // before `runApp` — so before this widget exists to listen.
    CaptureRouter.reviewRequest.value = memo.captureHash;

    await pumpApp(tester);

    expect(find.byType(MemoReviewContent), findsOneWidget,
        reason: 'a cold-launch tap must open the memo, not the dashboard');
    expect(inSheet('CHAIWALA JUNCTION'), findsOneWidget);
    expect(CaptureRouter.reviewRequest.value, isNull,
        reason: 'a request that has been answered must not stay pending');
  });

  testWidgets('an empty payload opens the inbox', (tester) async {
    CaptureRouter.reviewRequest.value = '';

    await pumpApp(tester);

    expect(find.text('Needs review'), findsWidgets);
    expect(CaptureRouter.reviewRequest.value, isNull);
  });

  testWidgets('a tap while the app is running opens the memo',
      (tester) async {
    final memo = memoFor('QWERTYSHOP');
    await MemoStore.insert(memo, db: db);
    await pumpApp(tester);
    expect(find.byType(MemoReviewContent), findsNothing);

    CaptureRouter.reviewRequest.value = memo.captureHash;
    await tester.pumpAndSettle();

    expect(inSheet('QWERTYSHOP'), findsOneWidget);
  });

  testWidgets('a second tap is not swallowed by the sheet already up',
      (tester) async {
    final first = memoFor('CHAIWALA JUNCTION');
    final second = memoFor('QWERTYSHOP');
    await MemoStore.insert(first, db: db);
    await MemoStore.insert(second, db: db);
    CaptureRouter.reviewRequest.value = first.captureHash;
    await pumpApp(tester);
    expect(inSheet('CHAIWALA JUNCTION'), findsOneWidget);

    // Arrives while the first sheet is still up. The old code early-returned
    // and left the hash in the notifier, where `ValueNotifier`'s equality
    // check then made every LATER tap on that same memo a silent no-op.
    CaptureRouter.reviewRequest.value = second.captureHash;
    await tester.pumpAndSettle();

    await closeSheet(tester);

    expect(inSheet('QWERTYSHOP'), findsOneWidget,
        reason: 'the deferred request must be presented, not dropped');
    expect(CaptureRouter.reviewRequest.value, isNull,
        reason: 'nothing may be left stranded in the notifier');
  });

  testWidgets('the same memo can be tapped again after its sheet closes',
      (tester) async {
    final memo = memoFor('CHAIWALA JUNCTION');
    await MemoStore.insert(memo, db: db);
    CaptureRouter.reviewRequest.value = memo.captureHash;
    await pumpApp(tester);
    await closeSheet(tester);
    expect(find.byType(MemoReviewContent), findsNothing);

    // The identical hash, a second time: the notifier must have been cleared,
    // or this write is equal to the value it holds and notifies nobody.
    CaptureRouter.reviewRequest.value = memo.captureHash;
    await tester.pumpAndSettle();

    expect(inSheet('CHAIWALA JUNCTION'), findsOneWidget);
  });
}
