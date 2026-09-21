/// What the user dismissed or muted on the insight strip. Device
/// preference, not financial data — SharedPreferences, the same tier as
/// the suggestion prompt's schedule. Mirrors InsightStore.swift.
library;

import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InsightStore {
  static const dismissedKey = 'insights.dismissed';
  static const mutedMerchantsKey = 'insights.mutedMerchants';
  static const mutedCategoriesKey = 'insights.mutedCategories';

  static Future<Suppressions> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Suppressions(
      dismissedIDs: (prefs.getStringList(dismissedKey) ?? const []).toSet(),
      mutedMerchants:
          (prefs.getStringList(mutedMerchantsKey) ?? const []).toSet(),
      mutedCategories:
          (prefs.getStringList(mutedCategoriesKey) ?? const []).toSet(),
    );
  }

  static Future<void> _insert(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(key) ?? [];
    if (!current.contains(value)) {
      current.add(value);
      await prefs.setStringList(key, current);
    }
  }

  static Future<void> dismiss(String id) => _insert(dismissedKey, id);

  static Future<void> mute(MuteTarget target) => switch (target) {
        MuteMerchant(:final merchantKey) =>
          _insert(mutedMerchantsKey, merchantKey),
        MuteCategory(:final category) => _insert(mutedCategoriesKey, category),
      };

  /// Drops dismissals for insights that no longer generate.
  static Future<void> prune(Set<String> live) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(dismissedKey) ?? const [];
    final kept = [
      for (final id in stored)
        if (live.contains(id)) id
    ];
    if (kept.length != stored.length) {
      await prefs.setStringList(dismissedKey, kept);
    }
  }

  /// Drops every dismissal and mute.
  ///
  /// "Erase all data" has to reach these. Dismissals are keyed by insight id
  /// and mutes by merchant key, so leaving them behind means a user who wipes
  /// the app and re-imports gets cards silently suppressed against data that
  /// no longer exists — and until an un-mute control lands (deferred to the
  /// next cycle; a mute is currently an action with no undo) the erase is the
  /// only way back.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dismissedKey);
    await prefs.remove(mutedMerchantsKey);
    await prefs.remove(mutedCategoriesKey);
  }

  static Future<void> resetForDebug() => clearAll();
}
