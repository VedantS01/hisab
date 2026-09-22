/// Android's half of near-real-time capture: bank and UPI alerts read off the
/// notification shade, parsed, and filed as pending memos.
///
/// The iOS twin is `Hisab/Intents/AddTransactionAlertIntent.swift`, and the
/// order of operations here is a deliberate transcription of it: stamp the
/// arrival, then the enable gate, then parse, then insert, then stamp the
/// capture. Only the allowlist check is extra, and it sits ahead of everything
/// because it is this platform's equivalent of "the automation fired at all".
///
/// ## READ_SMS is not an option and never will be
///
/// Reading the SMS inbox would be the obvious way to do this and is a closed
/// door: Play's SMS/Call-Log policy grants exceptions only through a process
/// that requires an APK published before 2019, which Hisab does not have. An
/// app declaring `READ_SMS` for this purpose is unpublishable, so
/// `NotificationListenerService` is the sanctioned mechanism and the manifest
/// must never gain an SMS permission.
///
/// ## The raw alert text is never persisted
///
/// The concatenated title+content exists only as a local `String` for the
/// duration of one `AlertParser.parse` call. It is never written to the
/// database (the memo table has no column that could hold it), never put in
/// SharedPreferences, and never logged. What survives is the parsed fields:
/// amount in integer paise, direction, payee, VPA, account tail, date.
///
/// ## Zero network
///
/// Nothing in this file, and nothing in the plugin it uses, opens a socket.
/// The plugin declares no permissions at all — see the manifest note in the
/// commit that added it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hisab_core/hisab_core.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import '../storage/database.dart';
import 'capture_prefs.dart';
import 'memo_store.dart';

/// Senders whose notifications are examined at all.
///
/// Bundled as an asset rather than compiled in, following the `FormatSpec`
/// precedent, so a new bank app extends the list without a code change.
/// Everything outside it is dropped before the text is even assembled, which
/// is the privacy boundary as much as it is a filter: Hisab never parses a
/// personal message.
class CaptureAllowlist {
  final int version;
  final Set<String> packages;

  const CaptureAllowlist({required this.version, required this.packages});

  factory CaptureAllowlist.fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return CaptureAllowlist(
      version: map['version'] as int,
      packages: {for (final p in map['packages'] as List) p as String},
    );
  }

  static const assetKey = 'assets/capture/allowlist.json';

  static Future<CaptureAllowlist> load() async =>
      CaptureAllowlist.fromJsonString(await rootBundle.loadString(assetKey));

  bool contains(String packageName) => packages.contains(packageName);
}

/// What one notification became. Returned so a test can assert the reason a
/// notification was dropped, not merely that no memo appeared.
enum CaptureOutcome {
  /// The sender is not an allowlisted bank, UPI or SMS app.
  notAllowlisted,

  /// A removal or an update of a notification already on the shade.
  notAPosting,

  /// Capture is switched off in settings.
  disabled,

  /// Allowlisted, but no transaction could be read out of the text.
  unparsed,

  /// Parsed, but this alert had already been captured.
  duplicate,

  /// Parsed and filed.
  captured,
}

class NotificationCapture {
  NotificationCapture._();

  static StreamSubscription<ServiceNotificationEvent>? _subscription;

  static bool get isRunning => _subscription != null;

  /// Whether the user has granted notification access in system settings.
  static Future<bool> isGranted() =>
      NotificationListenerService.isPermissionGranted();

  /// Opens the system's notification-access screen. Resolves true once access
  /// has been granted.
  static Future<bool> requestPermission() =>
      NotificationListenerService.requestPermission();

  /// Subscribes to the notification stream.
  ///
  /// ## Which database this uses, and why that is settled rather than assumed
  ///
  /// [MemoStore] is static and takes a required `db:`, so the handler needs an
  /// [AppDatabase] it can reach. It gets the app's one instance, passed in
  /// here, and that is correct *because of how this plugin delivers events*:
  /// the plugin's `NotificationListener` service broadcasts an Intent, and the
  /// receiver for that Intent is registered at runtime in the plugin's
  /// `onListen` — i.e. only while a Flutter engine has this stream subscribed.
  /// There is no background-isolate entrypoint. So the handler always runs on
  /// the main isolate of a live engine, alongside every other database caller,
  /// and there is exactly one sqlite connection.
  ///
  /// Opening a second [AppDatabase] from a background isolate would have been
  /// the alternative, and it is the thing to avoid: two connections to one
  /// file, two drift migration runs, and a memo written where the UI's
  /// in-memory state cannot see it.
  ///
  /// The cost of that same fact is in `stop()`'s note: capture is only live
  /// while the process is.
  static Future<void> start({
    required AppDatabase db,
    CaptureAllowlist? allowlist,
    Future<void> Function(PendingMemo memo)? onCaptured,
    DateTime Function()? clock,
  }) async {
    if (_subscription != null) return;
    final list = allowlist ?? await CaptureAllowlist.load();
    _subscription =
        NotificationListenerService.notificationsStream.listen((event) {
      // Fire-and-forget: the stream is not awaited by the platform, and an
      // exception escaping here would tear down the subscription and stop
      // capture silently.
      handle(
        packageName: event.packageName,
        title: event.title,
        content: event.content,
        hasRemoved: event.hasRemoved,
        db: db,
        allowlist: list,
        onCaptured: onCaptured,
        now: (clock ?? DateTime.now)(),
      ).catchError((Object error, StackTrace stack) {
        // Never log the notification itself, only that handling failed.
        debugPrint('capture: handling a notification failed: $error');
        return CaptureOutcome.unparsed;
      });
    });
  }

  /// Unsubscribes. The listener service itself stays bound to the system —
  /// only this process's interest in it ends.
  ///
  /// Note for anyone reading a "capture stopped working" report: because the
  /// plugin registers its broadcast receiver from `onListen` rather than in
  /// the manifest, capture lives and dies with the Flutter engine. After the
  /// process is killed, Android may rebind the listener service, but nothing
  /// re-subscribes the Dart stream until the app is opened again.
  static Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// One notification, start to finish. Separated from the stream so it can be
  /// tested without a platform channel.
  @visibleForTesting
  static Future<CaptureOutcome> handle({
    required String packageName,
    required String title,
    required String content,
    required bool hasRemoved,
    required AppDatabase db,
    required CaptureAllowlist allowlist,
    required DateTime now,
    Future<void> Function(PendingMemo memo)? onCaptured,
  }) async {
    // Ahead of everything, including the health stamp: a message from a friend
    // is not an alert that failed to parse, and counting it as one would make
    // the health indicator claim alerts are arriving when none are.
    if (!allowlist.contains(packageName)) return CaptureOutcome.notAllowlisted;

    // A removal is the same alert leaving the shade. Parsing it would re-run
    // the dedup guard for no reason.
    if (hasRemoved) return CaptureOutcome.notAPosting;

    // Unconditional, and BEFORE both the enable gate and the parse: an alert
    // that arrived while capture was off is still an arrival, and health's
    // whole job is to tell "nothing is reaching Hisab" apart from "everything
    // reaches Hisab and none of it parses". Mirrors the iOS intent exactly.
    await CapturePrefs.setLastAttemptAt(now);

    // The Settings toggle has to actually stop capture. A toggle that only
    // silences the notification while memos keep accruing is worse than no
    // toggle — the user believes they switched the feature off.
    if (!await CapturePrefs.isEnabled()) return CaptureOutcome.disabled;

    // The only place the raw text exists. It is not stored, not logged, and
    // goes out of scope with this call.
    final text = '$title $content'.trim();
    final memo = AlertParser.parse(text, now);
    if (memo == null) return CaptureOutcome.unparsed;

    final inserted = await MemoStore.insert(memo, db: db);
    // On a PARSED alert, whether or not it was new — a duplicate is still
    // proof the pipeline works, and the health indicator is about the
    // pipeline. Set on every parse, never on every notification.
    await CapturePrefs.setLastCaptureAt(now);
    if (!inserted) return CaptureOutcome.duplicate;

    // Task 16's CaptureNotifier goes here, and only on a true insert: a
    // re-posted alert must not produce a second banner.
    await onCaptured?.call(memo);
    return CaptureOutcome.captured;
  }
}
