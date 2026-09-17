/// Demo/test statement format. Port of SyntheticCSVParser.swift.
/// Header "hisab-demo-csv,v1"; optional "period,yyyy-MM-dd,yyyy-MM-dd";
/// rows: date,amountPaise,debit|credit,counterparty,reference,narration
library;

import 'dart:convert';

import '../domain.dart';
import '../generic_bank/statement_date.dart';

class SyntheticCsvParser implements StatementParser {
  @override
  final Source source;

  const SyntheticCsvParser({this.source = Source.gpay});

  static String? _decode(List<int> data) {
    try {
      return utf8.decode(data);
    } on FormatException {
      return null;
    }
  }

  @override
  bool canParse(List<int> data, String filename) =>
      _decode(data)?.startsWith('hisab-demo-csv,v1') ?? false;

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final text = _decode(data);
    if (text == null || !text.startsWith('hisab-demo-csv,v1')) {
      throw const UnrecognizedFormatException();
    }
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList()
      ..removeAt(0);

    DatePeriod? declaredPeriod;
    if (lines.isNotEmpty && lines.first.startsWith('period,')) {
      final parts = lines.first.split(',');
      final start =
          parts.length == 3 ? StatementDate.tryParse(parts[1], 'yyyy-MM-dd') : null;
      final end =
          parts.length == 3 ? StatementDate.tryParse(parts[2], 'yyyy-MM-dd') : null;
      if (start == null || end == null) {
        throw MalformedRowException(2, lines.first);
      }
      declaredPeriod = DatePeriod(start, end);
      lines.removeAt(0);
    }
    if (lines.isEmpty) throw const EmptyDocumentException();

    final transactions = <ParsedTransaction>[];
    for (var offset = 0; offset < lines.length; offset++) {
      final line = lines[offset];
      final fields = line.split(',');
      final date = fields.isNotEmpty
          ? StatementDate.tryParse(fields[0], 'yyyy-MM-dd')
          : null;
      final amount = fields.length > 1 ? int.tryParse(fields[1]) : null;
      final direction = fields.length > 2
          ? {'debit': Direction.debit, 'credit': Direction.credit}[fields[2]]
          : null;
      if (fields.length != 6 ||
          date == null ||
          amount == null ||
          amount <= 0 ||
          direction == null) {
        throw MalformedRowException(
            offset + (declaredPeriod == null ? 2 : 3), line);
      }
      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: amount,
        direction: direction,
        counterparty: fields[3],
        reference: fields[4].isEmpty ? null : fields[4],
        narration: fields[5],
      ));
    }
    return ParsedDocument(
        source: source,
        declaredPeriod: declaredPeriod,
        transactions: transactions);
  }
}
