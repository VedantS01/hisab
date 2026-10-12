/// A reader's proposal of a statement table's columns, accepted only when the
/// balance chain closes under it. Port of ProposedMapping.swift, plus the
/// label vocabulary and reply parsing an on-device model reader shares.
library;

import '../domain.dart';
import '../money.dart';
import 'chain_interpreter.dart';
import 'column_inference.dart';
import 'normalized_table.dart';
import 'statement_layout.dart';

/// Which column of a statement table holds what, as a reader proposes it.
/// Indices into the table's rows; null where the statement has no such column.
class ColumnRoles {
  final int date;
  final int narration;
  final int? reference;
  final int? debit;
  final int? credit;
  final int? amount;
  final int? drcr;
  final int balance;

  const ColumnRoles(
      {required this.date,
      required this.narration,
      this.reference,
      this.debit,
      this.credit,
      this.amount,
      this.drcr,
      required this.balance});

  /// The labels a model reader gives each column, one per column in column
  /// order.
  static const labels = [
    'date', 'valueDate', 'narration', 'reference', 'debit', 'credit',
    'amount', 'drcrMarker', 'balance', 'other',
  ];

  /// Roles from one label per column. With no column labelled balance, the
  /// rightmost money column: a model sometimes calls HDFC's "Closing Balance"
  /// an amount, and a running balance is the last money column on every
  /// statement it has seen.
  static ColumnRoles? fromLabels(List<String> kinds) {
    int? first(String kind) {
      final i = kinds.indexOf(kind);
      return i < 0 ? null : i;
    }

    final date = first('date') ?? first('valueDate');
    final narration = first('narration');
    int? balance = first('balance');
    if (balance == null) {
      final i = kinds.lastIndexWhere((k) => const ['debit', 'credit', 'amount'].contains(k));
      balance = i < 0 ? null : i;
    }
    if (date == null || narration == null || balance == null) return null;
    int? money(String kind) {
      for (var i = 0; i < kinds.length; i++) {
        if (kinds[i] == kind && i != balance) return i;
      }
      return null;
    }

    return ColumnRoles(
        date: date,
        narration: narration,
        reference: first('reference'),
        debit: money('debit'),
        credit: money('credit'),
        amount: money('amount'),
        drcr: first('drcrMarker'),
        balance: balance);
  }

  @override
  bool operator ==(Object other) =>
      other is ColumnRoles &&
      other.date == date &&
      other.narration == narration &&
      other.reference == reference &&
      other.debit == debit &&
      other.credit == credit &&
      other.amount == amount &&
      other.drcr == drcr &&
      other.balance == balance;

  @override
  int get hashCode =>
      Object.hash(date, narration, reference, debit, credit, amount, drcr, balance);

  @override
  String toString() =>
      'ColumnRoles(date: $date, narration: $narration, reference: $reference, debit: $debit, '
      'credit: $credit, amount: $amount, drcr: $drcr, balance: $balance)';
}

/// Reads a statement table's columns from its header and first rows — the
/// on-device language model in the app, a fixed answer in tests.
abstract interface class ColumnRoleProposer {
  Future<ColumnRoles?> propose(List<String>? header, List<List<String>> rows);
}

/// The prompt a text-only model reader is given, and how its reply is read:
/// one `n: label` line per column. Where the model has no constrained
/// decoding, the vocabulary is the constraint — anything outside it is
/// "other", a column it leaves out is "other".
class ColumnLabelPrompt {
  static String build(List<String>? header, List<List<String>> rows) {
    String line(List<String> cells) => [
          for (var i = 0; i < cells.length; i++)
            '$i: ${cells[i].length > 40 ? cells[i].substring(0, 40) : cells[i]}'
        ].join(' | ');
    final width = [header ?? const <String>[], ...rows].fold(0, (w, r) => r.length > w ? r.length : w);
    return 'You read the transaction table of a bank account statement and label every '
        'column with what it holds: date (the transaction date), valueDate (a second '
        'date column), narration (description or particulars), reference (cheque or '
        'reference number), debit (withdrawals), credit (deposits), amount (one column '
        'holding both debits and credits), drcrMarker (Dr or Cr), balance (the running '
        'balance), or other. A statement has one balance column, usually the last.\n\n'
        '${header == null ? '' : 'Header: ${line(header)}\n'}'
        'Rows:\n${rows.map(line).join('\n')}\n\n'
        'Answer with exactly $width lines, one per column from 0 to ${width - 1}, '
        'each "number: label", using only the labels above.';
  }

  static List<String> parse(String reply, int width) {
    final kinds = List.filled(width, 'other');
    final pattern = RegExp(r'^\W*(\d+)\W+([A-Za-z]+)');
    for (final raw in reply.split('\n')) {
      final m = pattern.firstMatch(raw.trim());
      if (m == null) continue;
      final column = int.parse(m.group(1)!);
      final label = ColumnRoles.labels
          .where((l) => l.toLowerCase() == m.group(2)!.toLowerCase())
          .firstOrNull;
      if (column < width && label != null) kinds[column] = label;
    }
    return kinds;
  }
}

/// A proposer's reading, held to the same standard as every other: the date
/// format comes from the cells, not the proposer, and the reading is accepted
/// only when every transaction's balance closes to the paisa under it. A wrong
/// proposal is a refusal, never an import.
///
/// Knowing the columns is what lets this go where [ColumnInference] can't:
/// rows whose date cell isn't a date at all (an opening-balance line, a total)
/// are set aside instead of sinking the table, and an opening-balance line's
/// balance anchors the first transaction — which is what lets an unsigned
/// amount column, whose direction only the balance reveals, be read at all.
class ProposedMapping {
  /// Rows shown to the proposer: enough to see each column's shape, few enough
  /// for an on-device model's context.
  static const sampleRows = 8;

  /// The first rows, and then the first row that fills each column they leave
  /// empty — a page of withdrawals says nothing about the deposits.
  static List<List<String>> sample(List<List<String>> body) {
    bool fills(List<String> row, int column) => column < row.length && row[column].isNotEmpty;
    final rows = body.take(sampleRows ~/ 2).toList();
    final width = body.fold(0, (w, r) => r.length > w ? r.length : w);
    for (var column = 0; column < width && rows.length < sampleRows; column++) {
      if (rows.any((r) => fills(r, column))) continue;
      final row = body.where((r) => fills(r, column)).firstOrNull;
      if (row != null) rows.add(row);
    }
    for (final row in body) {
      if (rows.length >= sampleRows) break;
      if (!rows.contains(row)) rows.add(row);
    }
    return rows;
  }

  static Future<InferenceResult?> read(NormalizedTable table, ColumnRoleProposer proposer) async {
    final (:header, rows: body) = ColumnInference.body(table);
    if (body.length < 2) return null;
    final ColumnRoles? proposal;
    try {
      proposal = await proposer.propose(header, sample(body));
    } catch (_) {
      return null;
    }
    if (proposal == null) return null;
    final roles = proposal;
    final width = body.fold(0, (w, r) => r.length > w ? r.length : w);
    final named = [
      roles.date, roles.narration, roles.balance,
      ...[roles.reference, roles.debit, roles.credit, roles.amount, roles.drcr].whereType<int>(),
    ];
    if (!named.every((c) => c >= 0 && c < width)) return null;

    String cell(List<String> row, int column) => column < row.length ? row[column] : '';
    // A row is a transaction when its date cell reads as a date; one that
    // looks like a date but won't parse sinks the reading in the chain.
    final dated = body.where((r) => DateShapes.looksLikeDate(cell(r, roles.date))).toList();
    if (dated.length < 2) return null;
    final format = ColumnInference.dateFormatParsingAll([for (final r in dated) cell(r, roles.date)]);
    if (format == null) return null;
    final first = table.rows.indexOf(dated.first);
    // The nearest number in the balance column above the first transaction:
    // an "Opening Balance" line, however few cells it has.
    int? opening;
    for (var i = first - 1; i >= 0 && opening == null; i--) {
      opening = Money.signedPaise(cell(table.rows[i], roles.balance));
    }

    ColumnMapping mapping({int? debit, int? credit, int? amount, int? drcr, bool unsigned = false}) =>
        ColumnMapping(
            date: roles.date,
            narration: roles.narration,
            reference: roles.reference,
            debit: debit,
            credit: credit,
            amount: amount,
            drcr: drcr,
            balance: roles.balance,
            amountIsUnsigned: unsigned,
            dateFormat: format);

    // The proposer's own reading first. Then the columns it called debit,
    // credit or amount are taken as money columns in any arrangement — a model
    // reading "Deposit Amt." calls it the amount — since only the right one
    // closes the chain: a swapped pair contradicts the balance.
    final money = <int>[];
    for (final column in [roles.debit, roles.credit, roles.amount].whereType<int>()) {
      if (column != roles.balance && !money.contains(column)) money.add(column);
    }
    final legs = <(int, int)>[];
    if (roles.debit != null &&
        roles.credit != null &&
        money.contains(roles.debit) &&
        money.contains(roles.credit) &&
        roles.debit != roles.credit) {
      legs.add((roles.debit!, roles.credit!));
    }
    for (final debit in money) {
      for (final credit in money) {
        if (credit != debit && !legs.contains((debit, credit))) legs.add((debit, credit));
      }
    }
    final candidates = [for (final (d, c) in legs) mapping(debit: d, credit: c)];
    final amounts = roles.amount != null && money.contains(roles.amount)
        ? [roles.amount!, ...money.where((c) => c != roles.amount)]
        : money;
    for (final amount in amounts) {
      if (roles.drcr != null && roles.drcr != amount) {
        candidates.add(mapping(amount: amount, drcr: roles.drcr));
      }
      // Signed if the column carries signs; else the chain decides.
      candidates.add(mapping(amount: amount));
      candidates.add(mapping(amount: amount, unsigned: true));
    }

    // With the opening line's balance first, so the first row is checked too;
    // without it — the first row trusted, as ColumnInference does — when that
    // line turns out not to be an opening balance. Every arrangement that
    // closes must read the same transactions; two different readings are a
    // refusal, as in ColumnInference.
    final starts = opening == null ? const <int?>[null] : <int?>[opening, null];
    InferenceResult? reading;
    for (final candidate in candidates) {
      for (final start in starts) {
        final outcome =
            ChainInterpreter.interpret(rows: dated, mapping: candidate, openingBalancePaise: start);
        if (outcome is! ChainValidated) continue;
        if (reading != null) {
          if (!_same(reading.transactions, outcome.transactions)) return null;
        } else {
          reading = InferenceResult(candidate, outcome.transactions);
        }
      }
    }
    return reading;
  }

  static bool _same(List<ParsedTransaction> a, List<ParsedTransaction> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
