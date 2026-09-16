/// Data-free format report. Port of FormatFingerprint.swift — header labels
/// verbatim, body cells only as digit/letter masks; by construction no
/// transaction value can appear.
library;

import 'dart:convert';

import 'column_inference.dart';
import 'normalized_table.dart';

class FormatFingerprint {
  final String container;
  final List<String> headerRow;
  final int columnCount;
  final int rowCount; // body rows below the header
  final List<String> cellShapes; // per-column dominant mask: digits→N, letters→A
  final String? bankNameGuess;

  const FormatFingerprint({
    required this.container,
    required this.headerRow,
    required this.columnCount,
    required this.rowCount,
    required this.cellShapes,
    required this.bankNameGuess,
  });

  static const supportAddress = 'vedantsaboo2001@gmail.com';

  /// Fixed nominative list scanned in header/furniture text only.
  static const knownBanks = [
    ('state bank|sbi', 'SBI'), ('icici', 'ICICI'), ('axis', 'Axis'),
    ('kotak', 'Kotak'), ('hdfc', 'HDFC'), ('idfc', 'IDFC First'),
    ('punjab national|pnb', 'PNB'), ('bank of baroda', 'Bank of Baroda'),
    ('canara', 'Canara'), ('yes bank', 'Yes Bank'), ('federal', 'Federal'),
    ('indusind', 'IndusInd'), ('union bank', 'Union Bank'), ('idbi', 'IDBI'),
  ];

  static FormatFingerprint make(NormalizedTable table) {
    final headerIndex = ColumnInference.detectHeader(table.rows);
    final headerRow =
        headerIndex == null ? <String>[] : List<String>.from(table.rows[headerIndex]);
    final bodyStart = headerIndex == null ? 0 : headerIndex + 1;
    final body = table.rows.skip(bodyStart).toList();
    var width = headerRow.length;
    for (final row in body) {
      if (row.length > width) width = row.length;
    }

    final shapes = <String>[];
    for (var column = 0; column < width; column++) {
      final counts = <String, int>{};
      for (final row in body) {
        if (column >= row.length || row[column].isEmpty) continue;
        final m = mask(row[column]);
        counts[m] = (counts[m] ?? 0) + 1;
      }
      String dominant = '';
      var best = 0;
      counts.forEach((m, c) {
        if (c > best) {
          dominant = m;
          best = c;
        }
      });
      shapes.add(dominant);
    }

    // Bank name: header row + furniture rows above it. Never body rows.
    final furnitureText = table.rows
        .take(bodyStart)
        .expand((r) => r)
        .join(' ')
        .toLowerCase();
    String? guess;
    for (final (pattern, name) in knownBanks) {
      if (RegExp(pattern).hasMatch(furnitureText)) {
        guess = name;
        break;
      }
    }

    return FormatFingerprint(
      container: table.container,
      headerRow: headerRow,
      columnCount: width,
      rowCount: body.length,
      cellShapes: shapes,
      bankNameGuess: guess,
    );
  }

  /// Digits become N, letters become A; punctuation and spaces survive.
  static String mask(String value) => value.split('').map((ch) {
        if (RegExp(r'\d').hasMatch(ch)) return 'N';
        if (RegExp(r'[a-zA-Z]').hasMatch(ch)) return 'A';
        return ch;
      }).join();

  String emailBody({required String appVersion}) {
    final lines = <String>['Hisab format request (v$appVersion)', ''];
    lines.add('Container: $container');
    final bank = bankNameGuess;
    if (bank != null) lines.add('Bank (guessed): $bank');
    lines.add('Columns: $columnCount, body rows: $rowCount');
    lines.add(headerRow.isNotEmpty
        ? 'Header: ${headerRow.join(' | ')}'
        : 'Header: none detected');
    lines.add('Column shapes: ${cellShapes.join(' | ')}');
    lines.add('');
    lines.add(
        'This report contains column labels and value shapes only — no transactions.');
    return lines.join('\n');
  }

  /// User-initiated mailto link; the app itself never transmits anything.
  Uri mailtoUri({required String appVersion}) => Uri(
        scheme: 'mailto',
        path: supportAddress,
        queryParameters: {
          'subject': 'Hisab format request',
          'body': emailBody(appVersion: appVersion),
        },
      );

  Map<String, dynamic> toJson() => {
        'container': container,
        'headerRow': headerRow,
        'columnCount': columnCount,
        'rowCount': rowCount,
        'cellShapes': cellShapes,
        'bankNameGuess': bankNameGuess,
      };

  String toJsonString() => jsonEncode(toJson());
}
