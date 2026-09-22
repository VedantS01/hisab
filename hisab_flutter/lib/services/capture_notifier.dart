/// "What was this?" — the notification that turns a captured alert into a
/// categorization rule, and the switch that governs capture as a whole.
///
/// Twin of `Hisab/Services/CaptureNotifier.swift`. Everything about *whether*
/// to interrupt and *what* to put on the banner is shared logic living in
/// `hisab_core` ([CategoryMatcher], [NotificationPolicy], [CategoryRanker]);
/// this file is the Android delivery of it plus the small amount of state a
/// notification button leaves behind.
///
/// ## Two asymmetries with iOS, both deliberate
///
/// 1. **Action buttons are per-notification here, and there are only three of
///    them.** iOS bakes action titles into a registered
///    `UNNotificationCategory`, and `setNotificationCategories` *replaces* the
///    registered set — so two pending iOS notifications with different
///    choice-sets leave the older one's buttons stale (a limitation recorded
///    in the Swift twin). `AndroidNotificationAction`s are attached to the
///    notification itself, so that limitation does not exist here and no
///    category registry is needed.
///
///    But Android's standard notification template draws at most THREE
///    actions and silently discards the rest — verified on an API 36 emulator,
///    where a fourth action simply did not appear. iOS shows three categories
///    plus "Later"; that is four, so one of them would vanish without saying
///    so. The three slots go to the three categories, and there is no "Later"
///    button: on Android, tapping the notification body opens the memo
///    (exactly what "Later" routes to) and swiping the notification away is
///    the platform's own "not now". [laterActionId] is still honoured by
///    [respond] so a banner posted by an older build keeps working.
/// 2. **A category button foregrounds the app.** The actions are built with
///    `showsUserInterface: true`. The alternative — a button handled without
///    opening Hisab — routes through the plugin's `ActionBroadcastReceiver`
///    into a **background isolate**, which would need its own [AppDatabase]:
///    two sqlite connections to one file, two drift migration runs, and a
///    write the live UI cannot see. Task 15 settled that question against a
///    second connection, and this follows it. The cost is one extra app
///    launch; the benefit is that the assignment lands in the same database
///    every other caller uses.
///
/// ## Known limitation: capture does not survive process death
///
/// The `notification_listener_service` plugin registers its broadcast receiver
/// at runtime from `onListen`, with no background-isolate entrypoint. After a
/// force-stop Android rebinds the listener service, but nothing re-subscribes
/// the Dart stream until Hisab is opened again — so **no memo is written, and
/// `lastAttemptAt` does not even move**, until the app is reopened. Verified on
/// an API 36 emulator in Task 15; not worked around here, because the fix is a
/// platform-channel rewrite of the listener.
///
/// What this file owes that limitation is honesty: because the silence is
/// indistinguishable from "no alerts arrived", `CaptureHealth` (see
/// `widgets/needs_review_section.dart`) drives off `lastAttemptAt` and says so
/// at the 3-day mark rather than leaving the user to discover the silence
/// themselves.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../storage/database.dart';
import 'capture_prefs.dart';
import 'memo_store.dart';
import 'notification_capture.dart';
import 'queries.dart';

/// One notification Hisab has decided to post: the copy, the one-tap answers,
/// and when it may be delivered.
///
/// Separated from delivery so the whole decision — the enable gate, the
/// "did the matcher already know this payee" gate, the daily cap, quiet hours
/// and the button set — is testable without a platform channel.
@immutable
class CaptureNotificationPlan {
  final String captureHash;
  final String title;
  final String body;

  /// Up to three categories, from [CategoryRanker.topCategories].
  final List<String> categories;

  /// Null to deliver immediately; an instant to hold until (quiet hours).
  final DateTime? fireAt;

  const CaptureNotificationPlan({
    required this.captureHash,
    required this.title,
    required this.body,
    required this.categories,
    this.fireAt,
  });

  /// Action ids as they go onto the notification, in order.
  ///
  /// Capped at [CaptureNotifier.maxActions] because Android's template drops
  /// anything past the third action without a word. The cap is applied HERE,
  /// where it can be asserted, rather than left to the platform.
  List<String> get actionIds => [
        for (final category in categories.take(CaptureNotifier.maxActions))
          '${CaptureNotifier.categoryActionPrefix}$category',
      ];
}

/// A category chosen from a NOTIFICATION button, waiting to be offered as a
/// rule the next time Hisab is opened.
///
/// Persisted rather than held in memory: the assignment itself is already in
/// the database, but the offer — the durable value this whole feature exists
/// to produce — would otherwise be lost if the process died before the user
/// saw it.
@immutable
class RuleOffer {
  final String captureHash;
  final String category;
  const RuleOffer({required this.captureHash, required this.category});

  @override
  bool operator ==(Object other) =>
      other is RuleOffer &&
      other.captureHash == captureHash &&
      other.category == category;

  @override
  int get hashCode => Object.hash(captureHash, category);

  @override
  String toString() => 'RuleOffer($captureHash, $category)';
}

/// Where a notification response wants the UI to go. `RootTabs` listens.
///
/// Two separate notifiers rather than one, because the two are answered by
/// different sheets: a body tap or "Later" opens the memo, while a category
/// button has already assigned and only leaves a rule to offer.
class CaptureRouter {
  CaptureRouter._();

  /// Capture hash of a memo to open for review, or null.
  static final ValueNotifier<String?> reviewRequest = ValueNotifier(null);

  /// Bumped whenever a rule offer is queued, so a foregrounded app learns of
  /// it — SharedPreferences is not observable.
  static final ValueNotifier<int> offerGeneration = ValueNotifier(0);
}

class CaptureNotifier {
  CaptureNotifier._();

  /// Prefix of an action id carrying a category name. The remainder is the
  /// category VERBATIM — never split on "|", because a user may legitimately
  /// name a category "Rent | Utilities" and splitting would assign "Rent ".
  static const categoryActionPrefix = 'CAT|';

  /// The iOS "Later" action id. Not drawn on Android (see the file header),
  /// but still recognised by [respond] — it carries no category, so it routes
  /// to the memo like any other non-category response.
  static const laterActionId = 'MEMO_LATER';

  /// Android's standard notification template draws at most three actions and
  /// discards the rest in silence.
  static const maxActions = 3;

  static const channelId = 'hisab.capture';
  static const channelName = 'Captured alerts';
  static const channelDescription =
      'Asks what an uncategorized payment was, with one-tap answers.';

  /// The key `CapturePrefs.clearCapturedData`'s prefix sweep was written in
  /// anticipation of. It carries a capture hash and a category the user chose
  /// for a named payee, so an "erase all data" must collect it — and does,
  /// without that method needing to change.
  static const ruleOfferKey = 'capture.pendingRuleOffer';

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Whether this platform can deliver a capture notification at all.
  /// The Flutter app ships on Android; everything here is a no-op elsewhere,
  /// including in `flutter test`, where no platform channel exists.
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // MARK: - lifecycle

  /// Called once from `main`. Initializes delivery, replays a response that
  /// launched the app, and — only if the user has capture switched on —
  /// subscribes the notification listener.
  ///
  /// This is the ONLY place capture starts. There is no dart-define shortcut
  /// any more: Task 15 added `CAPTURE_ENABLE` and a bare
  /// `NotificationCapture.start()` so the service was reachable before a
  /// toggle existed, and the toggle now exists (`CaptureSetupScreen`, and the
  /// Settings entry that links to it).
  static Future<void> init({
    required AppDatabase db,
    required Ruleset ruleset,
  }) async {
    if (!_supported) return;
    if (!_initialized) {
      _initialized = true;
      tz_data.initializeTimeZones();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          // Fire-and-forget: the plugin does not await this, and an exception
          // escaping it would be swallowed with the user's tap.
          respond(
            actionId: response.actionId,
            captureHash: response.payload,
            db: db,
          );
        },
      );
      // A response that LAUNCHED the app is not delivered through the callback
      // above — the app was not running to receive it. Without this, tapping a
      // category button on a cold phone opens Hisab and does nothing else.
      final launch = await plugin.getNotificationAppLaunchDetails();
      final response = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && response != null) {
        await respond(
          actionId: response.actionId,
          captureHash: response.payload,
          db: db,
        );
      }
    }
    if (await CapturePrefs.isEnabled()) {
      await NotificationCapture.start(
        db: db,
        onCaptured: (memo) =>
            considerNotifying(memo: memo, db: db, ruleset: ruleset),
      );
    }
  }

  /// The one way capture is switched on or off.
  ///
  /// Going OFF must actually STOP CAPTURE, not merely stop notifying: the
  /// stream is unsubscribed, so no memo is written at all. A toggle that
  /// silenced the banner while memos kept accruing would be worse than no
  /// toggle, because the user believes they switched the feature off.
  /// `NotificationCapture.handle` re-checks the flag as well, so the gate
  /// holds even for an event already in flight.
  ///
  /// Pending (held) notifications are dropped too. A quiet-hours hold is an
  /// alarm hours away; without this it would fire the morning AFTER the user
  /// switched capture off, and its buttons would still assign a category.
  /// Already-delivered banners cannot be withdrawn without erasing the user's
  /// notification history — [respond]'s own gate is what makes those inert.
  static Future<void> setEnabled(
    bool enabled, {
    required AppDatabase db,
    required Ruleset ruleset,
  }) async {
    await CapturePrefs.setEnabled(enabled);
    if (!_supported) return;
    if (!enabled) {
      await NotificationCapture.stop();
      await plugin.cancelAllPendingNotifications();
      return;
    }
    await requestNotificationPermission();
    await NotificationCapture.start(
      db: db,
      onCaptured: (memo) =>
          considerNotifying(memo: memo, db: db, ruleset: ruleset),
    );
  }

  /// POST_NOTIFICATIONS, from Android 13 onwards. Declared by the
  /// flutter_local_notifications plugin's own manifest, not by Hisab's.
  static Future<bool> requestNotificationPermission() async {
    if (!_supported) return false;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// What the system will currently do with a banner, so the setup screen can
  /// say so rather than leaving a user with a toggle that looks on and a
  /// feature that never speaks.
  static Future<bool> areNotificationsEnabled() async {
    if (!_supported) return false;
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  // MARK: - deciding

  /// Everything about whether to notify and what to say, given data. Pure.
  ///
  /// Returns null when no banner should be posted at all — which is the
  /// common case: Hisab only asks about payees its own rules could NOT
  /// categorize, precisely the memory-decay case this feature exists for.
  static CaptureNotificationPlan? plan({
    required PendingMemo memo,
    required List<CategoryRule> rules,
    required List<SpendRecord> records,
    required Ruleset ruleset,
    required DateTime now,
    required int sentToday,
  }) {
    final auto = CategoryMatcher(rules).category(memo.payee);
    if (auto != Categorizer.uncategorized &&
        auto != Categorizer.miscellaneous) {
      return null;
    }

    final decision =
        NotificationPolicy.decide(now: now, sentToday: sentToday);
    final DateTime? fireAt;
    switch (decision) {
      case NotificationSuppress():
        return null;
      case NotificationSend():
        fireAt = null;
      case NotificationHold(until: final until):
        fireAt = until;
    }

    return CaptureNotificationPlan(
      captureHash: memo.captureHash,
      title: 'What was this?',
      body: '${Money.formatPaise(memo.amountPaise)} to ${memo.payee}',
      categories: CategoryRanker.topCategories(
          records: records, now: now, limit: 3, ruleset: ruleset),
      fireAt: fireAt,
    );
  }

  /// Notifies only when Hisab could not categorize the payee.
  ///
  /// Wired into `NotificationCapture.handle`'s `onCaptured`, which fires only
  /// on a TRUE insert — a re-posted alert must not produce a second banner.
  static Future<void> considerNotifying({
    required PendingMemo memo,
    required AppDatabase db,
    required Ruleset ruleset,
    DateTime? now,
  }) async {
    // Capture off means capture off, notifications included. Reached only via
    // an event already in flight when the toggle moved, but that is exactly
    // the case the user would report as "I turned it off and it still spoke".
    if (!await CapturePrefs.isEnabled()) return;

    // `notifiedAtMs` is read HERE, which is what makes writing it legitimate.
    // What it covers is re-entry for a memo that was not re-inserted — the
    // quiet-hours retry. `MemoStore.insert` declines a duplicate rather than
    // upserting, so the field cannot be reset out from under this guard.
    final stored = await MemoStore.find(hash: memo.captureHash, db: db);
    if (stored?.notifiedAtMs != null) return;

    final at = now ?? DateTime.now();
    final ruleRows = await db.select(db.storedCategoryRules).get();
    final txns = await db.select(db.storedTransactions).get();
    final matches = await db.select(db.storedMatches).get();
    final rules = Queries.rules(ruleRows);
    final plan = CaptureNotifier.plan(
      memo: memo,
      rules: rules,
      records:
          Queries.suggestionRecords(txns, matches, CategoryMatcher(rules)),
      ruleset: ruleset,
      now: at,
      sentToday: await CapturePrefs.notificationsSentToday(at),
    );
    if (plan == null) return;

    if (!await deliver(plan, now: at)) return;

    // Only a notification the system ACCEPTED may spend the daily budget or
    // stamp the memo. Recording regardless would be the app lying to itself
    // about work it did not do.
    //
    // KNOWN LIMITATION, carried over from the Swift twin deliberately: the
    // send is recorded against `at` — the day the notification was SCHEDULED —
    // even when the quiet-hours branch held it until tomorrow morning. Ten
    // memos held after 22:00 therefore spend today's budget and are delivered
    // tomorrow, when a fresh budget allows ten more. The clean fix is to
    // record against the DELIVERY day, but the cap is checked inside
    // `NotificationPolicy.decide` before a delivery date exists, so the fix is
    // circular and would reopen shared core logic.
    await CapturePrefs.recordNotification(at);
    await (db.update(db.storedPendingMemos)
          ..where((t) => t.captureHash.equals(memo.captureHash)))
        .write(StoredPendingMemosCompanion(
            notifiedAtMs: Value(at.toUtc().millisecondsSinceEpoch)));
  }

  /// Posts (or schedules) one plan. False when nothing was posted, so the
  /// caller does not spend a notification slot on a banner that never existed.
  @visibleForTesting
  static Future<bool> deliver(
    CaptureNotificationPlan plan, {
    required DateTime now,
  }) async {
    if (!_supported) return false;
    // The banner IS the feature — the one-tap answers are the whole point —
    // so a build where notifications are switched off in system settings must
    // not burn a slot or stamp the memo.
    if (!await areNotificationsEnabled()) return false;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        actions: [
          for (final category in plan.categories.take(maxActions))
            AndroidNotificationAction(
              '$categoryActionPrefix$category',
              category,
              // See the file header: a foregrounding action keeps the write on
              // the main isolate and its single database connection.
              showsUserInterface: true,
            ),
        ],
      ),
    );

    final id = notificationId(plan.captureHash);
    final fireAt = plan.fireAt;
    try {
      if (fireAt == null) {
        await plugin.show(
          id: id,
          title: plan.title,
          body: plan.body,
          notificationDetails: details,
          payload: plan.captureHash,
        );
      } else {
        await plugin.zonedSchedule(
          id: id,
          title: plan.title,
          body: plan.body,
          scheduledDate: tz.TZDateTime.from(fireAt, _kolkata),
          notificationDetails: details,
          payload: plan.captureHash,
          // Inexact deliberately: an exact alarm would need
          // SCHEDULE_EXACT_ALARM in Hisab's manifest and a second permission
          // prompt, and "some time after 08:00" is the whole requirement.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (error) {
      // Never log the alert. Only that delivery failed.
      debugPrint('capture: could not post a notification: $error');
      return false;
    }
    return true;
  }

  static tz.Location get _kolkata => tz.getLocation('Asia/Kolkata');

  /// A stable 31-bit id from a capture hash. Android notification ids are
  /// ints; the hash is what identifies a memo everywhere else, so the id is
  /// derived from it rather than counted, and re-posting the same alert
  /// replaces its own banner instead of stacking a second one.
  @visibleForTesting
  static int notificationId(String captureHash) {
    if (captureHash.isEmpty) return 0;
    final head = captureHash.length >= 8
        ? captureHash.substring(0, 8)
        : captureHash;
    return (int.tryParse(head, radix: 16) ?? head.hashCode) & 0x7FFFFFFF;
  }

  // MARK: - responding

  /// The category an action id carries, or null if it carries none.
  ///
  /// Strips the known prefix; never splits on "|".
  static String? categoryFromActionId(String? actionId) {
    if (actionId == null || !actionId.startsWith(categoryActionPrefix)) {
      return null;
    }
    final category = actionId.substring(categoryActionPrefix.length);
    return category.isEmpty ? null : category;
  }

  /// Applies one notification response: a category button assigns and queues
  /// the rule offer; anything else routes the user to the memo.
  static Future<void> respond({
    required String? actionId,
    required String? captureHash,
    required AppDatabase db,
  }) async {
    // A banner delivered before the user switched capture off is still on the
    // shade, and its buttons still work. Without this gate the app would write
    // to the database — an assignment plus a rule offer — hours after the
    // feature was turned off. The tap still opens Hisab, because Android opens
    // an app for a foregrounding action whatever the app then does; it simply
    // does nothing else.
    if (!await CapturePrefs.isEnabled()) return;

    if (captureHash == null || captureHash.isEmpty) {
      // A payload-less notification can still be tapped. Land the user
      // somewhere real rather than on whatever tab was last open.
      CaptureRouter.reviewRequest.value = '';
      return;
    }
    final category = categoryFromActionId(actionId);
    if (category == null) {
      // "Later" and the body tap both land here.
      CaptureRouter.reviewRequest.value = captureHash;
      return;
    }
    final memo = await MemoStore.find(hash: captureHash, db: db);
    if (memo == null) {
      CaptureRouter.reviewRequest.value = captureHash;
      return;
    }
    await MemoStore.assign(category: category, memo: memo, db: db);
    await queueOffer(RuleOffer(captureHash: captureHash, category: category));
  }

  // MARK: - the queued rule offer

  /// Every queued offer, oldest first.
  ///
  /// Stored as a FLAT list of hash/category pairs so a category name
  /// containing the separator is never split apart. A one-deep slot would
  /// contradict the reason the offer is persisted at all: two unknown payees
  /// in one afternoon is an ordinary day, not a corner case.
  static Future<List<RuleOffer>> pendingRuleOffers() async {
    final prefs = await SharedPreferences.getInstance();
    final parts = prefs.getStringList(ruleOfferKey) ?? const [];
    if (parts.length.isOdd) return const [];
    return [
      for (var i = 0; i < parts.length; i += 2)
        RuleOffer(captureHash: parts[i], category: parts[i + 1]),
    ];
  }

  /// Queues one offer, replacing any earlier offer for the SAME memo: two taps
  /// on one memo are the user changing their mind, and only the last answer is
  /// worth offering as a rule.
  static Future<void> queueOffer(RuleOffer offer) async {
    final offers = [
      for (final existing in await pendingRuleOffers())
        if (existing.captureHash != offer.captureHash) existing,
      offer,
    ];
    await _writeOffers(offers);
    CaptureRouter.offerGeneration.value++;
  }

  /// Drops the offer for one memo, whether the user accepted it or not.
  static Future<void> clearOffer(String captureHash) async {
    final offers = [
      for (final existing in await pendingRuleOffers())
        if (existing.captureHash != captureHash) existing,
    ];
    await _writeOffers(offers);
  }

  static Future<void> _writeOffers(List<RuleOffer> offers) async {
    final prefs = await SharedPreferences.getInstance();
    if (offers.isEmpty) {
      await prefs.remove(ruleOfferKey);
      return;
    }
    await prefs.setStringList(ruleOfferKey, [
      for (final offer in offers) ...[offer.captureHash, offer.category],
    ]);
  }
}
