/// Conservative column inference. Port of ColumnInference.swift — accepts a
/// result only when exactly one distinct interpretation closes the balance
/// chain; zero candidates or conflicting winners mean null. Never guesses.
library;

import '../money.dart';
import '../domain.dart';
import 'chain_interpreter.dart';
import 'normalized_table.dart';
import 'statement_date.dart';

class InferenceResult {
  final ColumnMapping mapping;
  final List<ParsedTransaction> transactions;
  const InferenceResult(this.mapping, this.transactions);
}

class ColumnInference {
  static const candidateDateFormats = [
    'dd/MM/yyyy', 'dd/MM/yy', 'dd-MM-yyyy',
    'dd MMM yyyy', 'dd-MMM-yyyy', 'dd-MMM-yy', 'yyyy-MM-dd',
  ];

  static InferenceResult? infer(NormalizedTable table) {
    final headerIndex = detectHeader(table.rows);
    final start = headerIndex == null ? 0 : headerIndex + 1;
    final body = <List<String>>[];
    for (final row in table.rows.skip(start)) {
      final nonEmpty = row.where((c) => c.isNotEmpty).length;
      if (nonEmpty >= 3) body.add(row);
    }
    if (body.length < 2) return null;

    var width = 0;
    for (final row in body) {
      if (row.length > width) width = row.length;
    }
    if (width < 3) return null;

    List<String> cells(int column) =>
        body.map((r) => column < r.length ? r[column] : '').toList();

    final dateColumns = <(int, String)>[];
    final numericFull = <int>[];
    final numericSparse = <int>[];
    final drcrColumns = <int>[];
    final textColumns = <(int, int)>[]; // (column, averageLength)

    for (var column = 0; column < width; column++) {
      final values = cells(column);
      final format = _dateFormatParsingAll(values);
      if (format != null) {
        dateColumns.add((column, format));
        continue;
      }
      final nonEmpty = values.where((v) => v.isNotEmpty).toList();
      final numericCount =
          nonEmpty.where((v) => Money.signedPaise(v) != null).length;
      if (nonEmpty.isNotEmpty && numericCount == nonEmpty.length) {
        if (nonEmpty.length == values.length) numericFull.add(column);
        numericSparse.add(column);
        continue;
      }
      final drcrCount = nonEmpty
          .where((v) => v.toLowerCase() == 'dr' || v.toLowerCase() == 'cr')
          .length;
      if (nonEmpty.isNotEmpty && drcrCount == nonEmpty.length) {
        drcrColumns.add(column);
        continue;
      }
      if (nonEmpty.isNotEmpty) {
        final total = nonEmpty.fold<int>(0, (acc, v) => acc + v.length);
        textColumns.add((column, total ~/ nonEmpty.length));
      }
    }

    if (dateColumns.isEmpty) return null;
    // Multiple date columns (Value Date + Txn Date): prefer the leftmost.
    final (dateColumn, format) = dateColumns.first;
    return _inferWithDate(dateColumn, format, numericFull, numericSparse,
        drcrColumns, textColumns, body);
  }

  static InferenceResult? _inferWithDate(
      int dateColumn,
      String format,
      List<int> numericFull,
      List<int> numericSparse,
      List<int> drcrColumns,
      List<(int, int)> textColumns,
      List<List<String>> body) {
    if (textColumns.isEmpty) return null;
    var narrationColumn = textColumns.first.$1;
    var bestLength = textColumns.first.$2;
    for (final (column, avg) in textColumns) {
      if (avg > bestLength) {
        narrationColumn = column;
        bestLength = avg;
      }
    }
    int? referenceColumn;
    var shortest = 1 << 30;
    for (final (column, avg) in textColumns) {
      if (column == narrationColumn) continue;
      if (avg < shortest) {
        referenceColumn = column;
        shortest = avg;
      }
    }

    final mappings = <ColumnMapping>[];
    for (final balance in numericFull) {
      final others = numericSparse.where((c) => c != balance).toList();
      for (final debit in others) {
        for (final credit in others) {
          if (credit == debit) continue;
          mappings.add(ColumnMapping(
              date: dateColumn,
              narration: narrationColumn,
              reference: referenceColumn,
              debit: debit,
              credit: credit,
              balance: balance,
              dateFormat: format));
        }
      }
      for (final amount in others) {
        if (!numericFull.contains(amount)) continue;
        mappings.add(ColumnMapping(
            date: dateColumn,
            narration: narrationColumn,
            reference: referenceColumn,
            amount: amount,
            balance: balance,
            dateFormat: format));
        for (final drcr in drcrColumns) {
          mappings.add(ColumnMapping(
              date: dateColumn,
              narration: narrationColumn,
              reference: referenceColumn,
              amount: amount,
              drcr: drcr,
              balance: balance,
              dateFormat: format));
        }
      }
    }

    ColumnMapping? winnerMapping;
    List<ParsedTransaction>? winnerTxns;
    for (final mapping in mappings) {
      final outcome = ChainInterpreter.interpret(rows: body, mapping: mapping);
      if (outcome is! ChainValidated) continue;
      if (winnerTxns == null) {
        winnerMapping = mapping;
        winnerTxns = outcome.transactions;
      } else if (!_sameTxns(winnerTxns, outcome.transactions)) {
        return null; // two different valid readings — refuse to choose
      }
    }
    if (winnerMapping == null || winnerTxns == null) return null;
    return InferenceResult(winnerMapping, winnerTxns);
  }

  static bool _sameTxns(List<ParsedTransaction> a, List<ParsedTransaction> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The first row that names columns rather than containing data: ≥2 cells
  /// matching header vocabulary and no date-parseable cell.
  static int? detectHeader(List<List<String>> rows) {
    final keywords = RegExp(
        'date|narration|particular|description|remarks|debit|credit|withdraw|deposit|amount|balance|ref|cheque',
        caseSensitive: false);
    for (var index = 0; index < rows.length; index++) {
      var keywordHits = 0;
      var hasDate = false;
      for (final cell in rows[index]) {
        if (cell.isEmpty) continue;
        if (keywords.hasMatch(cell)) keywordHits++;
        if (_dateFormatParsingAll([cell]) != null) hasDate = true;
      }
      if (keywordHits >= 2 && !hasDate) return index;
    }
    return null;
  }

  static String? _dateFormatParsingAll(List<String> values) {
    final nonEmpty = values.where((v) => v.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return null;
    for (final candidate in candidateDateFormats) {
      var allParse = true;
      for (final value in nonEmpty) {
        if (StatementDate.tryParse(value, candidate) == null) {
          allParse = false;
          break;
        }
      }
      if (allParse) return candidate;
    }
    return null;
  }
}
