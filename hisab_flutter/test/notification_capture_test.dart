// Android notification capture, the sender allowlist, and the privacy
// guarantees around both.
//
// `NotificationCapture.handle` is the whole pipeline minus the platform
// channel, so everything here runs without a device. What CANNOT be covered
// from a unit test is whether the plugin keeps delivering events after the app
// process is killed — that is a device question, answered in the commit
// message.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/capture_prefs.dart';
import 'package:hisab/services/demo_data.dart';
import 'package:hisab/services/memo_store.dart';
import 'package:hisab/services/notification_capture.dart';
import 'package:hisab/storage/database.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime ist(int year, int month, int day, [int hour = 0, int minute = 0]) =>
    DateTime.utc(year, month, day, hour, minute).subtract(istOffset);

const smsPackage = 'com.google.android.apps.messaging';
const alertBody = 'Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA '
    'vedant@okaxis. Ref 123456789012.';

final testAllowlist = CaptureAllowlist(
    version: 1, packages: const {smsPackage, 'com.phonepe.app'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CaptureAllowlist', () {
    test('the bundled asset parses and carries the senders that matter',
        () async {
      final list = CaptureAllowlist.fromJsonString(
          File('assets/capture/allowlist.json').readAsStringSync());
      expect(list.version, 1);
      // The three SMS apps are the ones that carry bank alerts on most Indian
      // phones; without them the feature has almost no input.
      expect(list.contains('com.google.android.apps.messaging'), isTrue);
      expect(list.contains('com.samsung.android.messaging'), isTrue);
      expect(list.contains('com.android.mms'), isTrue);
      expect(list.contains('com.phonepe.app'), isTrue);
      expect(list.contains('com.whatsapp'), isFalse,
          reason: 'a personal-messaging app must never be examined');
      expect(list.packages, hasLength(11));
    });

    test('the asset is registered with the bundle', () {
      // CaptureAllowlist.load() reads it through rootBundle; an unregistered
      // asset would throw only at runtime on a device.
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('- assets/capture/'));
    });
  });

  group('the manifest never asks for SMS', () {
    // A guard, not a description. READ_SMS would be the obvious way to build
    // this feature and is permanently closed: Play grants the exception only
    // through a process that requires an APK published before 2019. An app
    // that declares it for this purpose cannot be published, so this must fail
    // loudly the moment anyone adds one.
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    /// Comments stripped: the manifest's own comment explains at length why
    /// READ_SMS is closed, and a raw substring search over the file would
    /// match that explanation. What must be absent is the DECLARATION.
    final declarations =
        manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    test('READ_SMS, RECEIVE_SMS and READ_CALL_LOG are all absent', () {
      expect(declarations.contains('READ_SMS'), isFalse);
      expect(declarations.contains('RECEIVE_SMS'), isFalse);
      expect(declarations.contains('READ_CALL_LOG'), isFalse);
      // Belt and braces: whatever the name, no SMS-family permission at all.
      expect(declarations.contains('android.permission.SEND_SMS'), isFalse);
      expect(RegExp('uses-permission').hasMatch(declarations), isFalse,
          reason: 'Hisab declares no runtime permissions whatsoever; the '
              'listener service is bound by the system instead');
    });

    test('no INTERNET permission — zero network is a store-listing promise',
        () {
      expect(declarations.contains('android.permission.INTERNET'), isFalse);
    });

    test('the notification listener service is declared and system-bound', () {
      expect(
          manifest.contains('notification.listener.service.NotificationListener'),
          isTrue);
      expect(
          manifest
              .contains('android.permission.BIND_NOTIFICATION_LISTENER_SERVICE'),
          isTrue);
      expect(
          manifest.contains(
              'android.service.notification.NotificationListenerService'),
          isTrue);
    });

    test('the hisab:// deep link resolves to the main activity', () {
      expect(manifest.contains('android:scheme="hisab"'), isTrue);
      expect(manifest.contains('android.intent.category.BROWSABLE'), isTrue);
    });
  });

  group('NotificationCapture.handle', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() async => db.close());

    Future<CaptureOutcome> handle({
      String packageName = smsPackage,
      String title = 'HDFC Bank',
      String content = alertBody,
      bool hasRemoved = false,
      DateTime? now,
      Future<void> Function(PendingMemo memo)? onCaptured,
    }) =>
        NotificationCapture.handle(
          packageName: packageName,
          title: title,
          content: content,
          hasRemoved: hasRemoved,
          db: db,
          allowlist: testAllowlist,
          now: now ?? ist(2026, 9, 22, 14, 30),
          onCaptured: onCaptured,
        );

    test('an allowlisted alert becomes a memo', () async {
      await CapturePrefs.setEnabled(true);
      expect(await handle(), CaptureOutcome.captured);

      final memos = await MemoStore.all(db);
      expect(memos, hasLength(1));
      expect(memos.single.amountPaise, 45000);
      expect(memos.single.payee, 'vedant@okaxis');
      expect(memos.single.accountTail, '1234');
    });

    test('the stored memo carries no trace of the notification text',
        () async {
      await CapturePrefs.setEnabled(true);
      await handle(content: '$alertBody Secret personal postscript.');

      // Every text column of the row, concatenated. The postscript is the
      // canary: it is in the notification and must be in nothing that
      // survives it.
      final row = (await MemoStore.all(db)).single;
      final stored = [row.payee, row.payeeNormalized, row.vpa, row.accountTail,
        row.note, row.captureHash, row.direction].join(' ');
      expect(stored.contains('Secret'), isFalse);
      expect(stored.contains('postscript'), isFalse);
      expect(stored.contains('debited'), isFalse);
    });

    test('a package outside the allowlist is dropped before anything else',
        () async {
      await CapturePrefs.setEnabled(true);
      expect(await handle(packageName: 'com.whatsapp'),
          CaptureOutcome.notAllowlisted);
      expect(await MemoStore.all(db), isEmpty);
      expect(await CapturePrefs.lastAttemptAt(), isNull,
          reason: 'a friend\'s message is not an alert that failed to parse; '
              'stamping it would make health claim alerts are arriving');
    });

    test('with capture off no memo is written, but the arrival is recorded',
        () async {
      // The iOS twin of this is P1: a toggle that only silences the
      // notification while memos keep accruing is worse than no toggle.
      expect(await CapturePrefs.isEnabled(), isFalse);
      expect(await handle(), CaptureOutcome.disabled);
      expect(await MemoStore.all(db), isEmpty);

      expect(await CapturePrefs.lastAttemptAt(), ist(2026, 9, 22, 14, 30),
          reason: 'an alert that arrived while capture was off still arrived');
      expect(await CapturePrefs.lastCaptureAt(), isNull);
    });

    test('a removal is not a capture', () async {
      await CapturePrefs.setEnabled(true);
      expect(await handle(hasRemoved: true), CaptureOutcome.notAPosting);
      expect(await MemoStore.all(db), isEmpty);
    });

    test('an allowlisted notification with no transaction in it', () async {
      await CapturePrefs.setEnabled(true);
      expect(
          await handle(title: 'Airtel', content: 'Your plan expires tomorrow.'),
          CaptureOutcome.unparsed);
      expect(await MemoStore.all(db), isEmpty);
      expect(await CapturePrefs.lastAttemptAt(), isNotNull);
      expect(await CapturePrefs.lastCaptureAt(), isNull,
          reason: 'health must be able to tell "nothing arrives" from '
              '"everything arrives and none of it parses"');
    });

    test('the same alert re-posted does not make a second memo', () async {
      await CapturePrefs.setEnabled(true);
      expect(await handle(), CaptureOutcome.captured);

      // Android re-posts a notification as an update; the alert text is
      // identical and only the capture time moves.
      expect(await handle(now: ist(2026, 9, 22, 16, 0)),
          CaptureOutcome.duplicate);
      expect(await MemoStore.all(db), hasLength(1));
    });

    test('the notifier hook fires on a new memo and not on a duplicate',
        () async {
      await CapturePrefs.setEnabled(true);
      final notified = <int>[];
      Future<void> hook(PendingMemo memo) async =>
          notified.add(memo.amountPaise);

      await handle(onCaptured: hook);
      await handle(onCaptured: hook, now: ist(2026, 9, 22, 16, 0));
      expect(notified, [45000],
          reason: 'a re-posted alert must not produce a second banner');
    });

    test('the title is part of the text the parser sees', () async {
      await CapturePrefs.setEnabled(true);
      // Some senders put the amount in the title and the rest in the body.
      expect(
          await handle(
              title: 'Rs 99.00 debited from a/c XX1234', content: 'to ZEPTO'),
          CaptureOutcome.captured);
      final row = (await MemoStore.all(db)).single;
      expect(row.amountPaise, 9900);
      expect(row.payee, 'ZEPTO');
    });

    test('lastCaptureAt moves on a parsed duplicate, not on an unparsed alert',
        () async {
      await CapturePrefs.setEnabled(true);
      await handle(now: ist(2026, 9, 22, 14, 30));
      await handle(now: ist(2026, 9, 22, 16, 0));
      expect(await CapturePrefs.lastCaptureAt(), ist(2026, 9, 22, 16, 0),
          reason: 'a duplicate is still proof the pipeline works');

      await handle(
          title: 'Airtel',
          content: 'Your plan expires tomorrow.',
          now: ist(2026, 9, 22, 18, 0));
      expect(await CapturePrefs.lastCaptureAt(), ist(2026, 9, 22, 16, 0));
      expect(await CapturePrefs.lastAttemptAt(), ist(2026, 9, 22, 18, 0));
    });
  });

  group('erase all data', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() async => db.close());

    test('a pending memo does not survive an erase', () async {
      // The defect this fixes: eraseAll enumerated the five tables the app
      // shipped with, so a memo carrying payee, amount and date outlived a
      // user's explicit erase.
      final memo = PendingMemo(
        amountPaise: 45000,
        direction: Direction.debit,
        payee: 'Blue Tokai',
        vpa: 'bluetokai@okaxis',
        accountTail: '1234',
        date: ist(2026, 9, 22, 9, 15),
        capturedAt: ist(2026, 9, 22, 9, 15),
      );
      expect(await MemoStore.insert(memo, db: db), isTrue);
      await db.into(db.pinnedMonths).insert(
          PinnedMonthsCompanion.insert(monthKey: '2026-09'));

      await DemoData.eraseAll(db);

      expect(await MemoStore.all(db), isEmpty);
      expect(await db.select(db.pinnedMonths).get(), isEmpty);
    });

    test('capture health data is cleared, the user\'s own setting is not',
        () async {
      await CapturePrefs.setEnabled(true);
      await CapturePrefs.setLastAttemptAt(ist(2026, 9, 22, 9, 15));
      await CapturePrefs.setLastCaptureAt(ist(2026, 9, 22, 9, 15));
      await CapturePrefs.recordNotification(ist(2026, 9, 22, 9, 15));

      await CapturePrefs.clearCapturedData();

      expect(await CapturePrefs.lastAttemptAt(), isNull);
      expect(await CapturePrefs.lastCaptureAt(), isNull);
      expect(
          await CapturePrefs.notificationsSentToday(ist(2026, 9, 22, 9, 15)), 0);
      expect(await CapturePrefs.isEnabled(), isTrue,
          reason: 'erasing data is not a request to switch a feature off');
    });

    test('a future capture key is swept without anyone remembering to add it',
        () async {
      // The sweep is by prefix precisely so Task 16's
      // `capture.pendingRuleOffer` — a capture hash plus a category chosen for
      // a named payee — is covered the day it lands.
      SharedPreferences.setMockInitialValues({
        'capture.pendingRuleOffer': ['abc123', 'Food Delivery'],
        'insights.suppressed': ['unrelated'],
      });
      await CapturePrefs.clearCapturedData();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('capture.pendingRuleOffer'), isNull);
      expect(prefs.getStringList('insights.suppressed'), isNotNull,
          reason: 'the sweep is scoped to capture, not to everything');
    });
  });
}
