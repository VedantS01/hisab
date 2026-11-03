/// The insights agent's cards for the month just ended: written on the
/// first open after a month ends, or when the user asks, and kept until the
/// next month ends. Runs where Apple's models do; elsewhere the dashboard
/// keeps the native insights engine.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apple_model.dart';

class AgentInsightSet {
  final YearMonth month;
  final List<AgentInsight> cards;
  const AgentInsightSet(this.month, this.cards);
}

abstract final class AgentInsights {
  static const key = 'insights.agent';

  static final current = ValueNotifier<AgentInsightSet?>(null);
  static final running = ValueNotifier<bool>(false);

  /// The month a run on [now] is about: the calendar month before it, in IST.
  static YearMonth monthFor(DateTime now) =>
      YearMonth.fromDate(now).advancedBy(-1);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final parts = (json['month'] as String).split('-');
      current.value = AgentInsightSet(
        YearMonth(int.parse(parts[0]), int.parse(parts[1])),
        [
          for (final c in json['cards'] as List)
            AgentInsight.fromJson(Map<String, Object?>.from(c as Map))
        ],
      );
    } catch (_) {
      await prefs.remove(key);
    }
  }

  /// Runs the agent for the month before [now], unless it already has (or
  /// [force]), the ledger has nothing in that month, or no model is ready.
  /// A failed run stores nothing, so the next open tries again.
  static Future<void> maybeRun(List<InsightRecord> records,
      {required DateTime now, bool force = false, ModelRuntime? runtime}) async {
    final month = monthFor(now);
    if (running.value) return;
    if (!force && current.value?.month == month) return;
    if (!records.any((r) => YearMonth.fromDate(r.date) == month)) return;
    final model = runtime ?? appleModel;
    if (!(await model.status()).ready) return;
    running.value = true;
    try {
      final cards = await InsightsAgent(model)
          .run(tools: LedgerTools(records, now: now), month: month);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          key,
          jsonEncode({
            'month': '$month',
            'cards': [for (final c in cards) c.toJson()],
          }));
      current.value = AgentInsightSet(month, cards);
    } on ModelFailure catch (e) {
      debugPrint('insights agent: ${e.code}');
    } finally {
      running.value = false;
    }
  }

  /// For "Erase all data".
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    current.value = null;
  }
}
