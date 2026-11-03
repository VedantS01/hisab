/// Agent evals on this Mac, through the app's own Swift runtime
/// (tool/apple_model_cli). Usage, from packages/hisab_agents:
///
///   (cd ../../tool/apple_model_cli && swift build -c release)
///   dart run tool/eval.dart [columns|detection|insights|all] [--cloud]
///
/// Each suite prints one line per case and a score; the exit code is
/// non-zero when a suite scores below its bar, so it can gate changes to
/// prompts and schemas.
library;

import 'dart:io';

import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_agents/process_runtime.dart';
import 'package:hisab_core/hisab_core.dart';

const cli = '../../tool/apple_model_cli/.build/release/apple-model';
const fixtures = '../hisab_core/test/fixtures';
const formats = '../../assets/formats';

Future<void> main(List<String> args) async {
  final suite = args.firstWhere((a) => !a.startsWith('--'), orElse: () => 'all');
  final runtime = await ProcessRuntime.start(cli, cloud: args.contains('--cloud'));
  final status = await runtime.status();
  stdout.writeln('models: on-device ${status.onDevice}, cloud ${status.cloud}');
  var passed = true;
  try {
    if (suite == 'columns' || suite == 'all') passed &= await columns(runtime);
  } finally {
    await runtime.close();
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
