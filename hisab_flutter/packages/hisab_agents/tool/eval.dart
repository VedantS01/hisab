/// Agent evals on this Mac, through the app's own Swift runtime
/// (tool/apple_model_cli). Usage, from packages/hisab_agents:
///
///   (cd ../../tool/apple_model_cli && swift build -c release)
///   dart run tool/eval.dart [columns|detection|insights|all] [--cloud]
///   HISAB_GATEWAY_APP_KEY=… dart run tool/eval.dart detection --gateway
///
/// Each suite prints one line per case and a score; the exit code is
/// non-zero when a suite scores below its bar, so it can gate changes to
/// prompts and schemas.
library;

import 'dart:convert';
import 'dart:io';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_agents/process_runtime.dart';
import 'package:hisab_core/hisab_core.dart';

const cli = '../../tool/apple_model_cli/.build/release/apple-model';
const fixtures = '../hisab_core/test/fixtures';
const formats = '../../assets/formats';

Future<void> main(List<String> args) async {
  final suite = args.firstWhere((a) => !a.startsWith('--'), orElse: () => 'all');
  // --gateway: the cloud models through the live ai-gateway instead of
  // Apple's, with HISAB_GATEWAY_APP_KEY (and optionally HISAB_GATEWAY_URL)
  // in the environment. Spends this Mac's credits like a phone would.
  final ModelRuntime runtime;
  Future<void> Function() close = () async {};
  if (args.contains('--gateway')) {
    final appKey = Platform.environment['HISAB_GATEWAY_APP_KEY'];
    if (appKey == null || appKey.isEmpty) {
      stderr.writeln('--gateway needs HISAB_GATEWAY_APP_KEY in the environment');
      exit(2);
    }
    runtime = GatewayRuntime(
      base: Uri.parse(Platform.environment['HISAB_GATEWAY_URL'] ??
          'https://ai-gateway.draftsmith.workers.dev/v1/hisab'),
      appKey: appKey,
      tokens: MemoryTokenStore(),
    );
  } else {
    final process = await ProcessRuntime.start(cli, cloud: args.contains('--cloud'));
    runtime = process;
    close = process.close;
  }
  final status = await runtime.status();
  stdout.writeln('models: on-device ${status.onDevice}, cloud ${status.cloud}'
      '${status.quota == null ? '' : ' (quota ${status.quota})'}');
  var passed = true;
  try {
    if (suite == 'columns' || suite == 'all') passed &= await columns(runtime);
    if (suite == 'detection' || suite == 'all') passed &= await detection(runtime);
    if (suite == 'insights' || suite == 'all') passed &= await insights(runtime);
  } finally {
    await close();
  }
  exit(passed ? 0 : 1);
}

/// The column reader on every bundled bank format's synthetic fixture: the
/// reading passes when the transactions it lets through are exactly the
/// ones the format's own spec reads from the same file.
Future<bool> columns(ModelRuntime runtime) async {
  stdout.writeln('\n== columns');
  final cases = <(String, File, FormatSpec)>[];
  for (final spec in Directory(formats).listSync().whereType<File>()) {
    final format = FormatSpec.fromJsonString(spec.readAsStringSync());
    final id = format.id.replaceAll('-xlsx', '');
    final file = Directory(fixtures)
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('$id-fixture.'))
        .firstOrNull;
    if (file != null) cases.add((format.id, file, format));
  }
  var score = 0;
  for (final (id, file, spec) in cases) {
    final table = NormalizedTable.from(data: file.readAsBytesSync(), filename: file.path)!;
    final truth = SpecExecutor.execute(table: table, spec: spec);
    if (truth is! ChainValidated) {
      stdout.writeln('${id.padRight(14)} SKIP  spec does not read its own fixture');
      continue;
    }
    final watch = Stopwatch()..start();
    String verdict;
    final reader = _Recording(AppleColumnReader(runtime));
    final result = await ProposedMapping.read(table, reader);
    final ok = result != null && _same(result.transactions, truth.transactions);
    if (ok) score++;
    verdict = ok
        ? 'PASS'
        : reader.error != null
            ? 'FAIL  ${reader.error}'
            : result == null
                ? 'FAIL  refused: ${reader.roles} did not close the balance chain'
                : 'FAIL  read ${result.transactions.length}, spec reads ${truth.transactions.length}';
    stdout.writeln('${id.padRight(14)} $verdict  (${watch.elapsedMilliseconds} ms)');
  }
  stdout.writeln('columns: $score/${cases.length}');
  // The 1.5.0 on-device reader read all the bundled formats.
  return score == cases.length;
}

/// The detection agent on eval/detection.json: alert-parity's labelled
/// alerts and rejections plus synthetic emails, histories and non-payments.
/// A case passes when the detections are exactly the expected ones by
/// amount, direction, day and reference; account tail and payee are
/// reported, not gated.
Future<bool> detection(ModelRuntime runtime) async {
  stdout.writeln('\n== detection');
  final cases = (jsonDecode(File('eval/detection.json').readAsStringSync()) as Map)['cases'] as List;
  final agent = DetectionAgent(runtime);
  var score = 0, tails = 0, tailTotal = 0, payees = 0, payeeTotal = 0;
  for (final c in cases.cast<Map<String, Object?>>()) {
    final expected = [for (final e in c['expected'] as List) Map<String, Object?>.from(e as Map)];
    final watch = Stopwatch()..start();
    String verdict;
    try {
      final found = await agent.detect(c['text'] as String,
          receivedAt: DateTime.parse(c['receivedAt'] as String));
      String key(int paise, String direction, String day, String? ref) => '$paise $direction $day $ref';
      final got = {for (final d in found) key(d.amountPaise, d.direction.name, istDayString(d.date), d.reference)};
      final want = {
        for (final e in expected)
          key(e['amountPaise'] as int, e['direction'] as String, e['date'] as String, e['reference'] as String?)
      };
      final ok = got.length == found.length && got.length == want.length && got.containsAll(want);
      if (ok) score++;
      for (final e in expected) {
        final match = found.where((d) => d.amountPaise == e['amountPaise']).firstOrNull;
        if (e['accountTail'] != null) {
          tailTotal++;
          if (match?.accountTail == e['accountTail']) tails++;
        }
        if (e['counterparty'] != null) {
          payeeTotal++;
          if (match != null &&
              match.counterparty.toLowerCase().contains((e['counterparty'] as String).toLowerCase())) {
            payees++;
          }
        }
      }
      verdict = ok ? 'PASS' : 'FAIL  got $got\n${' ' * 32}want $want';
    } on ModelFailure catch (e) {
      verdict = 'FAIL  $e';
    }
    stdout.writeln('${(c['name'] as String).padRight(30).substring(0, 30)}  $verdict  (${watch.elapsedMilliseconds} ms)');
  }
  stdout.writeln('detection: $score/${cases.length}  (account tail $tails/$tailTotal, payee $payees/$payeeTotal)');
  return score >= cases.length * 0.9;
}


/// The insights agent on three months of an ordinary ledger, each with one
/// fact planted in October. A case passes when a card that survives the
/// grounding check names the planted fact; the dropped count is how often
/// the model quoted a number no tool said.
Future<bool> insights(ModelRuntime runtime) async {
  stdout.writeln('\n== insights');
  const cases = {
    'food-up': ['food', 'zomato'],
    'subscription': ['netflix'],
    'big-merchant': ['amazon', 'shopping'],
  };
  final tap = _Tap(runtime);
  final agent = InsightsAgent(tap);
  var score = 0, produced = 0, kept = 0;
  for (final MapEntry(key: name, value: words) in cases.entries) {
    final watch = Stopwatch()..start();
    String verdict;
    try {
      final tools = LedgerTools(_ledger(name), now: DateTime.utc(2026, 11, 3));
      final cards = await agent.run(tools: tools, month: YearMonth(2026, 10));
      final raw = (tap.last?.json['insights'] as List? ?? const []).length;
      produced += raw;
      kept += cards.length;
      final hit = cards.any((c) => words.any((w) =>
          '${c.title} ${c.body} ${c.category} ${c.merchant}'.toLowerCase().contains(w)));
      if (hit) score++;
      verdict = '${hit ? 'PASS' : 'FAIL'}  kept ${cards.length}/$raw  tools ${tools.calls.join(',')}';
      for (final c in cards) {
        verdict += '\n${' ' * 32}+ ${c.title} — ${c.body}';
      }
      if (cards.length < raw) verdict += '\n${' ' * 32}raw ${tap.last?.content}';
    } on ModelFailure catch (e) {
      verdict = 'FAIL  $e';
    }
    stdout.writeln('${name.padRight(30)}  $verdict  (${watch.elapsedMilliseconds} ms)');
  }
  stdout.writeln('insights: $score/${cases.length}  (cards kept $kept/$produced)');
  return score >= 2;
}

/// Three months of salary, rent, food, groceries and travel, plus [plant].
List<InsightRecord> _ledger(String plant) {
  final rows = <InsightRecord>[];
  void add(int month, int day, int rupees, String category, String merchant,
          {Direction direction = Direction.debit}) =>
      rows.add(InsightRecord(
          id: 'r${rows.length}',
          date: DateTime.utc(2026, month, day, 6),
          amountPaise: rupees * 100,
          direction: direction,
          category: category,
          merchant: merchant));
  // Only salary and rent repeat to the rupee; everyday spending wanders, as
  // it does.
  for (final (i, m) in [8, 9, 10].indexed) {
    add(m, 1, 85000, 'Income', 'ACME LTD', direction: Direction.credit);
    add(m, 5, 18000, 'Rent', 'LANDLORD');
    for (var d = 3 + i; d <= 27; d += 4 + i) {
      add(m, d, 380 + 35 * d % 140, 'Food', 'SWIGGY');
    }
    add(m, [12, 9, 16][i], [2240, 2675, 1930][i], 'Groceries', 'BIGBASKET');
    add(m, [24, 20, 27][i], [1810, 1365, 2120][i], 'Groceries', 'BLINKIT');
    add(m, [15, 18, 11][i], [1190, 960, 1415][i], 'Transport', 'UBER');
  }
  switch (plant) {
    case 'food-up':
      for (var d = 2; d <= 29; d += 3) {
        add(10, d, 520, 'Food', 'ZOMATO');
      }
    case 'subscription':
      for (final m in [6, 7, 8, 9, 10]) {
        add(m, 9, 649, 'Entertainment', 'NETFLIX');
      }
    case 'big-merchant':
      add(10, 18, 24999, 'Shopping', 'AMAZON');
  }
  return rows;
}

/// Keeps the last reply, so a case can show what the check dropped.
class _Tap implements ModelRuntime {
  final ModelRuntime inner;
  ModelReply? last;
  _Tap(this.inner);

  @override
  Future<ModelStatus> status() => inner.status();

  @override
  Future<ModelReply> respond(ModelRequest request) async => last = await inner.respond(request);
}

/// ProposedMapping swallows a proposer's exceptions (a failed reading is a
/// refusal); the eval wants to see them.
class _Recording implements ColumnRoleProposer {
  final ColumnRoleProposer inner;
  Object? error;
  ColumnRoles? roles;
  _Recording(this.inner);

  @override
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows) async {
    try {
      return roles = await inner.propose(header, rows);
    } catch (e) {
      error = e;
      rethrow;
    }
  }
}

bool _same(List<ParsedTransaction> a, List<ParsedTransaction> b) {
  String key(ParsedTransaction t) => '${t.date} ${t.amountPaise} ${t.direction.name}';
  final x = a.map(key).toList()..sort();
  final y = b.map(key).toList()..sort();
  return x.length == y.length && [for (var i = 0; i < x.length; i++) x[i] == y[i]].every((e) => e);
}
