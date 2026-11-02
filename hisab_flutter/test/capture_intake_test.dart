// The intake both platforms share, through the paths only iOS's Shortcuts
// action reaches: blank text, a note, an HTML email body, and the sentence
// Shortcuts says back. Android's listener tests cover the rest.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_intake.dart';
import 'package:hisab/services/capture_prefs.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime ist(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

const alertBody = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA '
    'vedant@okaxis. Ref 123456789012.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  final now = ist(2026, 9, 22, 14, 30);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => db.close());

  Future<IntakeResult> ingest(String text, {String? note}) =>
      CaptureIntake.ingest(text: text, note: note, db: db, now: now);

  test('capture off stores nothing and says how to turn it on', () async {
    final result = await ingest(alertBody);
    expect(result.outcome, IntakeOutcome.captureOff);
    expect(result.dialog, "Capture is off. Turn it on in Hisab's settings.");
    expect(await MemoStore.all(db), isEmpty);
    expect(await CapturePrefs.lastAttemptAt(), now,
        reason: 'an arrival while off is still an arrival');
  });

  test('blank text blames the automation, not the alert', () async {
    await CapturePrefs.setEnabled(true);
    final result = await ingest('  \n ');
    expect(result.outcome, IntakeOutcome.noText);
    expect(result.dialog, contains('Shortcut Input'));
  });

  test('a logged alert carries its note and says what it logged', () async {
    await CapturePrefs.setEnabled(true);
    final result = await ingest(alertBody, note: 'lunch');
    expect(result.outcome, IntakeOutcome.logged);
    expect(result.dialog, 'Logged ₹450.00 to vedant@okaxis.');
    expect((await MemoStore.all(db)).single.note, 'lunch');
    expect(await CapturePrefs.lastOutcome(), (IntakeOutcome.logged, now));
  });

  test('the same alert again is a duplicate, not a second memo', () async {
    await CapturePrefs.setEnabled(true);
    await ingest(alertBody);
    final again = await ingest(alertBody);
    expect(again.outcome, IntakeOutcome.duplicate);
    expect(again.dialog, 'Already logged ₹450.00.');
    expect(await MemoStore.all(db), hasLength(1));
  });

  test('an HTML email body is read through its markup', () async {
    await CapturePrefs.setEnabled(true);
    final result = await ingest('<html><body><style>p{color:red}</style>'
        '<p>$alertBody</p></body></html>');
    expect(result.outcome, IntakeOutcome.logged);
  });

  test('text with no transaction says so', () async {
    await CapturePrefs.setEnabled(true);
    final result = await ingest('Your OTP is 123456. Do not share it.');
    expect(result.outcome, IntakeOutcome.notAPayment);
    expect(result.dialog, 'No transaction found in that text.');
  });
}
