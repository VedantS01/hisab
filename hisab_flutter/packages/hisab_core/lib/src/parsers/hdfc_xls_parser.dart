/// HDFC legacy .xls export (CDF/BIFF8 via MinimalXls). Port of
/// HDFCXLSParser.swift — shares HdfcStatementTable so identities match the
/// PDF and TXT renditions exactly.
library;

import '../domain.dart';
import '../generic_bank/minimal_xls.dart';
import 'hdfc_common.dart';

class HdfcXlsParser implements StatementParser {
  @override
  Source get source => Source.hdfc;

  const HdfcXlsParser();

  Map<int, Map<int, String>>? _grid(List<int> data) {
    try {
      return MinimalXls.cells(data);
    } on XlsCorruptException {
      return null;
    }
  }

  @override
  bool canParse(List<int> data, String filename) {
    final grid = _grid(data);
    if (grid == null) return false;
    final texts = grid.values.expand((r) => r.values);
    return texts.contains('Chq./Ref.No.') &&
        texts.any((t) => t.contains('HDFC BANK'));
  }

  @override
  ParsedDocument parse(List<int> data, {String? password}) {
    final grid = _grid(data);
    if (grid == null) throw const UnrecognizedFormatException();

    MapEntry<int, Map<int, String>>? headerRow;
    for (final entry in grid.entries) {
      if (entry.value.containsValue('Chq./Ref.No.')) {
        headerRow = entry;
        break;
      }
    }
    if (headerRow == null) throw const UnrecognizedFormatException();
    int? column(String title) {
      for (final entry in headerRow!.value.entries) {
        if (entry.value == title) return entry.key;
      }
      return null;
    }

    final dateCol = column('Date');
    final narrationCol = column('Narration');
    final refCol = column('Chq./Ref.No.');
    final withdrawalCol = column('Withdrawal Amt.');
    final depositCol = column('Deposit Amt.');
    final balanceCol = column('Closing Balance');
    if (dateCol == null ||
        narrationCol == null ||
        refCol == null ||
        withdrawalCol == null ||
        depositCol == null ||
        balanceCol == null) {
      throw const UnrecognizedFormatException();
    }

    final dateRegex = RegExp(r'^\d{2}/\d{2}/\d{2}$');
    final rows = <HdfcRow>[];
    final sortedKeys = grid.keys.toList()..sort();
    for (final rowIndex in sortedKeys) {
      if (rowIndex <= headerRow.key) continue;
      final row = grid[rowIndex];
      final date = row?[dateCol];
      if (row == null || date == null || !dateRegex.hasMatch(date)) continue;
      rows.add(HdfcRow(
        dateText: date,
        narration: row[narrationCol] ?? '',
        refText: row[refCol],
        withdrawalText: row[withdrawalCol],
        depositText: row[depositCol],
        balanceText: row[balanceCol],
      ));
    }

    final allText = grid.values.expand((r) => r.values).join('\n');
    return HdfcStatementTable.parse(
      rows: rows,
      openingBalancePaise: null,
      period: HdfcStatementTable.periodIn(allText),
    );
  }
}
