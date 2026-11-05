/// Apple's model reading a statement table's columns: the iOS counterpart of
/// the Gemini Nano reader on Android, and a port of the Swift app's
/// OnDeviceColumnReader — one enum property per column, described by its
/// header and first values, greedy sampling. Nothing it says is trusted
/// until the balance chain closes under it (ProposedMapping).
library;

import 'package:hisab_core/hisab_core.dart';

import '../runtime.dart';

class AppleColumnReader implements ColumnRoleProposer {
  final ModelRuntime runtime;
  const AppleColumnReader(this.runtime);

  static const instructions = 'You read the transaction table of a bank account statement and '
      'label every column with what it holds: date (the transaction date), valueDate (a '
      'second date column), narration (description or particulars), reference (cheque or '
      'reference number), debit (withdrawals), credit (deposits), amount (one column holding '
      'both debits and credits), drcrMarker (Dr or Cr), balance (the running balance), or '
      'other. A statement has one balance column, usually the last.';

  @override
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows) async {
    final width =
        [header ?? const <String>[], ...rows].fold(0, (w, r) => r.length > w ? r.length : w);
    if (width == 0) return null;
    try {
      final reply = await runtime.respond(ModelRequest(
        instructions: instructions,
        prompt: prompt(header, rows),
        schema: schema(header, rows, width),
        model: ModelChoice.onDevice,
        greedy: true,
        transform: true,
      ));
      final json = reply.json;
      return ColumnRoles.fromLabels(
          [for (var i = 0; i < width; i++) json['column$i'] as String? ?? 'other']);
    } on ModelFailure catch (e) {
      if (e.code != 'refused') rethrow;
    }
    // Guided generation keeps the default guardrails, which refuse some
    // statements' names and handles; plain text gets the permissive ones.
    // Same reading, in the text form the Gemini Nano reader uses.
    final reply = await runtime.respond(ModelRequest(
      instructions: '',
      // Without the last line Apple's model answers with the header names.
      prompt: '${ColumnLabelPrompt.build(header, rows)}\n\n'
          'Labels: ${ColumnRoles.labels.join(', ')}. Write a label from this list after '
          'each number, for example "0: date", never the column\'s own header.',
      model: ModelChoice.onDevice,
      greedy: true,
      transform: true,
    ));
    return ColumnRoles.fromLabels(ColumnLabelPrompt.parse(reply.content, width));
  }

  static String prompt(List<String>? header, List<List<String>> rows) {
    String line(List<String> cells) => [
          for (var i = 0; i < cells.length; i++)
            '$i: ${cells[i].length > 40 ? cells[i].substring(0, 40) : cells[i]}'
        ].join(' | ');
    return '${header == null ? '' : 'Header: ${line(header)}\n'}'
        'Rows:\n${rows.map(line).join('\n')}';
  }

  static Map<String, Object?> schema(List<String>? header, List<List<String>> rows, int width) {
    String clip(String s, int n) => s.length > n ? s.substring(0, n) : s;
    return Schema.object('Columns', {
      for (var i = 0; i < width; i++)
        'column$i': Schema.ref('Kind', description: () {
          final title = header != null && i < header.length ? header[i] : '';
          final values = [
            for (final row in rows.take(3))
              if (i < row.length && row[i].isNotEmpty) "'${clip(row[i], 30)}'"
          ];
          return 'Column $i'
              '${title.isEmpty ? '' : ", headed '$title'"}'
              '${values.isEmpty ? ', mostly empty' : ', values like ${values.join(', ')}'}';
        }()),
    }, defs: {
      'Kind': Schema.string(oneOf: ColumnRoles.labels),
    });
  }
}
