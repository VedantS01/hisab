import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisab/services/agent_insights.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Runtime implements ModelRuntime {
  final bool ready;
  final bool fail;
  int runs = 0;
  _Runtime({this.ready = true, this.fail = false});

  @override
  Future<ModelStatus> status() async =>
      ModelStatus(onDevice: ready ? 'available' : 'deviceNotEligible', cloud: 'notEntitled');

  @override
  Future<ModelReply> respond(ModelRequest request) async {
    runs++;
    if (fail) throw const ModelFailure('failed');
    // The tools are never called here, so no card can quote a number and
    // every one is dropped: what is under test is when the agent runs.
    return ModelReply(content: jsonEncode({'insights': []}), model: 'onDevice');
  }
}

void main() {
  final now = DateTime.utc(2026, 11, 3, 6);
  final october = [
    InsightRecord(
        id: 'a',
        date: DateTime.utc(2026, 10, 12, 6),
        amountPaise: 45000,
        direction: Direction.debit,
        category: 'Food',
        merchant: 'SWIGGY'),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AgentInsights.current.value = null;
  });

  test('the first open after a month ends writes it once', () async {
    final runtime = _Runtime();
    await AgentInsights.maybeRun(october, now: now, runtime: runtime);
    await AgentInsights.maybeRun(october, now: now, runtime: runtime);
    expect(runtime.runs, 1);
    expect(AgentInsights.current.value!.month, YearMonth(2026, 10));

    // Kept across launches.
    AgentInsights.current.value = null;
    await AgentInsights.load();
    expect(AgentInsights.current.value!.month, YearMonth(2026, 10));

    await AgentInsights.maybeRun(october, now: now, runtime: runtime, force: true);
    expect(runtime.runs, 2);
  });

  test('nothing to read, no model, or a failed run writes nothing', () async {
    final runtime = _Runtime();
    await AgentInsights.maybeRun(october, now: DateTime.utc(2026, 10, 20), runtime: runtime);
    await AgentInsights.maybeRun(october, now: now, runtime: _Runtime(ready: false));
    await AgentInsights.maybeRun(october, now: now, runtime: _Runtime(fail: true));
    expect(runtime.runs, 0);
    expect(AgentInsights.current.value, isNull);
    expect((await SharedPreferences.getInstance()).getString(AgentInsights.key), isNull);
  });
}
