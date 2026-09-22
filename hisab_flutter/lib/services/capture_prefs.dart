/// Capture is a property of this device, not of the user's ledger — so it
/// lives in SharedPreferences beside InsightStore, never in the database.
/// Mirrors Hisab/Services/CapturePrefs.swift.
///
/// Swift stores the two timestamps as `Date` in UserDefaults; there is no
/// such type here, so they are millisecond epochs, matching the `*Ms`
/// convention the drift tables already use.
library;

import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CapturePrefs {
  CapturePrefs._();

  static const enabledKey = 'capture.enabled';
  static const lastCaptureKey = 'capture.lastCaptureAt';
  static const lastAttemptKey = 'capture.lastAttemptAt';
  static const notifyCountKey = 'capture.notifyCount';
  static const notifyDayKey = 'capture.notifyDay';

  /// Off by default. The user opts in.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
  }

  /// The last time an alert was PARSED successfully.
  static Future<DateTime?> lastCaptureAt() => _readDate(lastCaptureKey);

  static Future<void> setLastCaptureAt(DateTime value) =>
      _writeDate(lastCaptureKey, value);

  /// The last time an alert ARRIVED, whatever became of it — including one
  /// that arrived while capture was switched off, and one the parser could
  /// make nothing of.
  ///
  /// Health needs both timestamps because one cannot tell "the automation
  /// never fired" from "the automation fires but every parse fails", and
  /// those need opposite remediations: re-check your notification access,
  /// versus nothing you can do, wait for an update. A warning that
  /// confidently sends the user to fix a working listener is worse than no
  /// warning.
  static Future<DateTime?> lastAttemptAt() => _readDate(lastAttemptKey);

  static Future<void> setLastAttemptAt(DateTime value) =>
      _writeDate(lastAttemptKey, value);

  /// Notifications sent today, so a heavy UPI day cannot spam. Resets when
  /// the IST day changes.
  static Future<int> notificationsSentToday(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final today = istDayString(now);
    if (prefs.getString(notifyDayKey) != today) return 0;
    return prefs.getInt(notifyCountKey) ?? 0;
  }

  /// Not atomic: the read, increment and write are three steps, so two truly
  /// concurrent callers could lose an increment. The failure mode is
  /// under-counting toward the daily cap, never over-counting, so it cannot
  /// cause spam.
  static Future<void> recordNotification(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final today = istDayString(now);
    final count = await notificationsSentToday(now) + 1;
    await prefs.setString(notifyDayKey, today);
    await prefs.setInt(notifyCountKey, count);
  }

  /// Everything capture has learned about the user, for "Erase all data".
  ///
  /// Written as a PREFIX sweep rather than a list of the keys that exist
  /// today, deliberately. The same bug has already been shipped twice in this
  /// area — insight suppressions survived an erase and went on hiding cards
  /// about data the user no longer had, and `stored_pending_memos` was missed
  /// when the table was added — and both had the same cause: an erase path
  /// enumerating what existed when it was written. The one key still to come
  /// here is `capture.pendingRuleOffer` (Task 16, the iOS twin is in
  /// `CaptureNotifier`), which carries a capture hash and a category the user
  /// chose for a named payee. A sweep collects it the day it lands.
  ///
  /// [enabledKey] is deliberately kept: it is a device setting the user chose,
  /// not something Hisab learned about their spending, and silently switching
  /// a feature off is not what "erase my data" asks for. Everything else under
  /// `capture.` — both health timestamps, the notification counters — is
  /// derived from captured alerts and goes.
  static Future<void> clearCapturedData() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(keyPrefix) && key != enabledKey) {
        await prefs.remove(key);
      }
    }
  }

  static const keyPrefix = 'capture.';

  static Future<DateTime?> _readDate(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(key);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static Future<void> _writeDate(String key, DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value.toUtc().millisecondsSinceEpoch);
  }
}
