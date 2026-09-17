/// Applies a FormatSpec to a NormalizedTable. Port of SpecExecutor.swift —
/// specs are trusted for selection, never for correctness: output must still
/// close the balance chain.
library;

import 'chain_interpreter.dart';
import 'format_spec.dart';
import 'normalized_table.dart';
import 'statement_date.dart';

class SpecExecutor {
  /// Null when the spec does not match (no header row / detect gate failed).
  static ChainOutcome? execute(
      {required NormalizedTable table, required FormatSpec spec}) {
    final detect = spec.detectPatterns;
    if (detect != null && detect.isNotEmpty) {
      final whole =
          table.rows.map((r) => r.join('|')).join('\n');
      for (final pattern in detect) {
        if (!RegExp(pattern, caseSensitive: false).hasMatch(whole)) {
          return null;
        }
      }
    }

    final required = requiredRoles(spec.signConvention);
    final header = _findHeader(table, spec, required);
    if (header == null) return null;
    final (headerIndex, columns) = header;

    final furniture = <RegExp>[];
    for (final pattern in spec.furniturePatterns) {
      try {
        furniture.add(RegExp(pattern, caseSensitive: false));
      } on FormatException {
        return null;
      }
    }

    final body = <List<String>>[];
    for (final row in table.rows.skip(headerIndex + 1)) {
      if (row.every((c) => c.isEmpty)) continue;
      final joined = row.join('|');
      if (furniture.any((r) => r.hasMatch(joined))) continue;
      body.add(row);
    }
    if (body.isEmpty) return const ChainBroken(0, 'no body rows');

    final dateFormat = _pickDateFormat(spec.dateFormats, body, columns['date']!);
    if (dateFormat == null) {
      return const ChainBroken(0, 'no declared date format parses the body');
    }

    final mapping = ColumnMapping(
      date: columns['date']!,
      narration: columns['narration']!,
      reference: columns['reference'],
      debit: columns['debit'],
      credit: columns['credit'],
      amount: columns['amount'],
      drcr: columns['drcr'],
      balance: columns['balance']!,
      amountIsUnsigned: spec.signConvention == 'unsignedChain',
      dateFormat: dateFormat,
      referencePatterns: spec.referencePatterns ?? const [],
    );
    return ChainInterpreter.interpret(rows: body, mapping: mapping);
  }

  static List<String> requiredRoles(String signConvention) {
    switch (signConvention) {
      case 'debitCredit':
        return ['date', 'narration', 'balance', 'debit', 'credit'];
      case 'amountDRCR':
        return ['date', 'narration', 'balance', 'amount', 'drcr'];
      default:
        return ['date', 'narration', 'balance', 'amount'];
    }
  }

  /// First row where every required role's regex matches a distinct cell.
  static (int, Map<String, int>)? _findHeader(
      NormalizedTable table, FormatSpec spec, List<String> required) {
    final regexes = <String, RegExp>{};
    for (final entry in spec.headerPatterns.entries) {
      try {
        regexes[entry.key] = RegExp(entry.value, caseSensitive: false);
      } on FormatException {
        return null;
      }
    }
    for (final role in required) {
      if (!regexes.containsKey(role)) return null;
    }

    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      final columns = <String, int>{};
      final used = <int>{};
      var allFound = true;
      final optional = regexes.keys.where((k) => !required.contains(k)).toList()
        ..sort();
      for (final role in [...required, ...optional]) {
        final regex = regexes[role];
        if (regex == null) continue;
        int? found;
        for (var cellIndex = 0; cellIndex < row.length; cellIndex++) {
          if (used.contains(cellIndex)) continue;
          if (regex.hasMatch(row[cellIndex])) {
            found = cellIndex;
            break;
          }
        }
        if (found != null) {
          columns[role] = found;
          used.add(found);
        } else if (required.contains(role)) {
          allFound = false;
          break;
        }
      }
      if (allFound) return (rowIndex, columns);
    }
    return null;
  }

  static String? _pickDateFormat(
      List<String> candidates, List<List<String>> body, int dateColumn) {
    for (final candidate in candidates) {
      var allParse = true;
      for (final row in body) {
        final text = dateColumn < row.length ? row[dateColumn] : '';
        if (StatementDate.tryParse(text, candidate) == null) {
          allParse = false;
          break;
        }
      }
      if (allParse) return candidate;
    }
    return null;
  }
}
