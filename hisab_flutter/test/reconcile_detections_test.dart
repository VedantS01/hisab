// The Reconcile tab's detections: listed first with the likeliest row,
// editable in a sheet whose save re-matches the detection.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/design/design.dart';
import 'package:hisab/screens/reconciliation_screen.dart';
import 'package:hisab/services/detections.dart';
import 'package:hisab/services/import_service.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/state.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab/widgets/detection_edit_sheet.dart';
import 'package:hisab_core/hisab_core.dart';

final ruleset = Ruleset.fromJsonString(
    File('assets/rulesets/india-default.json').readAsStringSync());
final insightsConfig = InsightsConfig.fromJsonString(
    File('assets/insights/insights-config.json').readAsStringSync());

void main() {
  late AppDatabase db;
  late AppState state;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    state = AppState(
      db: db,
      importService: ImportService(
        db: db,
        resolver: ImportResolver(
            registry: liveRegistry(), specs: SpecStore.parseAll(const [])),
      ),
      ruleset: ruleset,
      insightsConfig: insightsConfig,
    );
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
          theme: HisabDesign.light(), home: const ReconciliationScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a detection is listed with its likeliest row; the editor saves and re-matches',
      (tester) async {
    // A row the detection could be, by amount and day alone: a suggestion,
    // not a merge.
    final rowId = (await ImportService.insertCapturedAlert(
        ParsedTransaction(
          date: DateTime.utc(2026, 9, 22, 6),
          amountPaise: 45000,
          direction: Direction.debit,
          counterparty: 'SOMEONE',
          reference: 'REF123456',
          narration: 'UPI/SOMEONE',
        ),
        db: db))!;
    final seen = PendingMemo(
      amountPaise: 45000,
      direction: Direction.debit,
      payee: 'Blue Tokai',
      date: DateTime.utc(2026, 9, 22, 7),
      capturedAt: DateTime.utc(2026, 9, 22, 7),
    );
    await MemoStore.insert(seen, db: db);
    await Detections.settle(seen.captureHash, db: db);
    expect((await MemoStore.find(hash: seen.captureHash, db: db))!.mergedTxnUuid, isNull);

    await pump(tester);
    expect(find.text('Detections'), findsOneWidget);
    expect(find.text('Blue Tokai'), findsOneWidget);
    expect(find.text('Possible'), findsOneWidget);
    // The row is also in the month's "App only" list below; the suggestion
    // names it once more, next to the detection.
    expect(
        find.descendant(
            of: find.byType(SuggestionRow),
            matching: find.textContaining('SOMEONE')),
        findsOneWidget);

    await tester.tap(find.text('Blue Tokai'));
    await tester.pumpAndSettle();
    expect(find.byType(DetectionEditor), findsOneWidget);
    expect(find.byKey(const Key('detection-amount')), findsOneWidget);

    // Naming the account the row's narration names turns the suggestion
    // into a link on save.
    await tester.enterText(find.byKey(const Key('detection-payee')), 'Someone');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Save'));
    await tester.pumpAndSettle();

    final after = (await MemoStore.find(hash: seen.captureHash, db: db))!;
    expect(after.payee, 'Someone');
    expect(after.mergedTxnUuid, rowId);
    expect(find.byType(DetectionEditor), findsNothing);
    expect(find.text('Detections'), findsNothing,
        reason: 'linked, it is no longer a detection');
  });

  testWidgets('Not this hides the row from the suggestions', (tester) async {
    await ImportService.insertCapturedAlert(
        ParsedTransaction(
          date: DateTime.utc(2026, 9, 22, 6),
          amountPaise: 45000,
          direction: Direction.debit,
          counterparty: 'SOMEONE',
          reference: 'REF123456',
          narration: 'UPI/SOMEONE',
        ),
        db: db);
    final seen = PendingMemo(
      amountPaise: 45000,
      direction: Direction.debit,
      payee: 'Blue Tokai',
      date: DateTime.utc(2026, 9, 22, 7),
      capturedAt: DateTime.utc(2026, 9, 22, 7),
    );
    await MemoStore.insert(seen, db: db);
    await pump(tester);
    expect(find.text('Possible'), findsOneWidget);
    await tester.tap(find.text('Not this'));
    await tester.pumpAndSettle();
    expect(find.text('Possible'), findsNothing);
    expect(find.textContaining('no match yet'), findsOneWidget);
  });
}
