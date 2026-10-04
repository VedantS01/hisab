// Runs the shipped regex AlertParser over JSONL alerts for the ml/ evaluation
// harness: stdin `{"id","text"}` lines, stdout `{"id","fields"}` lines in the
// shape of ml/src/hisab_ml/schema.py `Fields`. Dev tool, not part of the app.
import 'dart:convert';
import 'dart:io';

import 'package:hisab_core/hisab_core.dart';

// A receivedAt no real alert can carry, so a fallback date reads as "absent".
final _sentinel = DateTime.utc(2000, 1, 1, 6);

String _istDate(DateTime d) => d
    .toUtc()
    .add(const Duration(hours: 5, minutes: 30))
    .toIso8601String()
    .substring(0, 10);

Future<void> main() async {
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final input = jsonDecode(line) as Map<String, dynamic>;
    final memo = AlertParser.parse(input['text'] as String, _sentinel);
    final fields = memo == null
        ? {'is_txn': false}
        : {
            'is_txn': true,
            'direction': memo.direction.name,
            'amount_paise': memo.amountPaise,
            'payee': memo.payee,
            'vpa': memo.vpa,
            'own_acct_tail': memo.accountTail,
            'date_iso': memo.date.isAtSameMomentAs(_sentinel)
                ? null
                : _istDate(memo.date),
          };
    stdout.writeln(jsonEncode({'id': input['id'], 'fields': fields}));
  }
}
