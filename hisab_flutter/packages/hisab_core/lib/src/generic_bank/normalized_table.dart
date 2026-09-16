/// Container-neutral table. Port of NormalizedTable.swift. The PDF adapter is
/// injected (see [pdfLinesExtractor]) so the pure core stays free of the PDF
/// dependency until the parsers module wires it.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'minimal_xls.dart';

/// Injected by the parsers module: raw pdf bytes + password → lines of cells,
/// or null when unreadable. Kept as a mutable hook so NormalizedTable stays
/// dependency-light and testable.
List<List<String>>? Function(List<int> data, String? password)?
    pdfLinesExtractor;

class NormalizedTable {
  List<List<String>> rows;
  String container; // csv | txt | xlsx | xls | pdf

  NormalizedTable({required this.rows, required this.container});

  @override
  bool operator ==(Object other) =>
      other is NormalizedTable &&
      other.container == container &&
      _rowsEqual(other.rows, rows);
  @override
  int get hashCode => Object.hash(container, rows.length);

  static bool _rowsEqual(List<List<String>> a, List<List<String>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].length != b[i].length) return false;
      for (var j = 0; j < a[i].length; j++) {
        if (a[i][j] != b[i][j]) return false;
      }
    }
    return true;
  }

  static NormalizedTable? from(
      {required List<int> data, required String filename, String? password}) {
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'csv':
        final text = _decodeUtf8(data);
        if (text == null) return null;
        final rows = _lines(text).map(splitCsvLine).toList();
        return rows.isEmpty
            ? null
            : NormalizedTable(rows: rows, container: 'csv');
      case 'txt':
        final text = _decodeUtf8(data);
        if (text == null) return null;
        final rows = _lines(text).map(splitOnSpaceRuns).toList();
        return rows.isEmpty
            ? null
            : NormalizedTable(rows: rows, container: 'txt');
      case 'xlsx':
        final rows = _xlsxRows(data);
        return (rows == null || rows.isEmpty)
            ? null
            : NormalizedTable(rows: rows, container: 'xlsx');
      case 'xls':
        try {
          final grid = MinimalXls.cells(data);
          if (grid.isEmpty) return null;
          return NormalizedTable(rows: _densifyXls(grid), container: 'xls');
        } on XlsCorruptException {
          return null;
        }
      case 'pdf':
        final extractor = pdfLinesExtractor;
        if (extractor == null) return null;
        final rows = extractor(data, password);
        return (rows == null || rows.isEmpty)
            ? null
            : NormalizedTable(rows: rows, container: 'pdf');
      default:
        return null;
    }
  }

  static String? _decodeUtf8(List<int> data) {
    try {
      return utf8.decode(data);
    } on FormatException {
      return null;
    }
  }

  static List<String> _lines(String text) => text
      .split(RegExp(r'\r?\n'))
      .where((line) => line.isNotEmpty)
      .toList();

  static List<String> splitCsvLine(String line) {
    final cells = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (final ch in line.split('')) {
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ',' && !inQuotes) {
        cells.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    cells.add(current.toString());
    return cells.map((c) => c.trim()).toList();
  }

  static List<String> splitOnSpaceRuns(String line) => line
      .replaceAll('\t', '  ')
      .split('  ')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();

  /// XLSX: shared strings + the sheet with the most rows, densified A=0.
  static List<List<String>>? _xlsxRows(List<int> data) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(data);
    } catch (_) {
      return null;
    }
    List<int>? entry(String name) {
      for (final file in archive.files) {
        if (file.name == name) return file.content as List<int>;
      }
      return null;
    }

    final shared = <String>[];
    final ssData = entry('xl/sharedStrings.xml');
    if (ssData != null) {
      try {
        final doc = XmlDocument.parse(utf8.decode(ssData));
        for (final si in doc.findAllElements('si')) {
          shared.add(si.findAllElements('t').map((t) => t.innerText).join());
        }
      } catch (_) {
        return null;
      }
    }

    List<Map<String, String>>? best;
    for (final file in archive.files) {
      if (!file.name.startsWith('xl/worksheets/') ||
          !file.name.endsWith('.xml')) {
        continue;
      }
      try {
        final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
        final rows = <Map<String, String>>[];
        for (final row in doc.findAllElements('row')) {
          final cells = <String, String>{};
          for (final c in row.findAllElements('c')) {
            final ref = c.getAttribute('r') ?? '';
            final letters =
                ref.split('').takeWhile((ch) => RegExp(r'[A-Za-z]').hasMatch(ch)).join();
            final type = c.getAttribute('t') ?? '';
            final v = c.getElement('v')?.innerText ??
                c.getElement('is')?.findAllElements('t').map((t) => t.innerText).join() ??
                '';
            if (letters.isEmpty || v.isEmpty) continue;
            if (type == 's') {
              final index = int.tryParse(v);
              if (index != null && index < shared.length) {
                cells[letters] = shared[index];
              }
            } else {
              cells[letters] = v;
            }
          }
          rows.add(cells);
        }
        if (best == null || rows.length > best.length) best = rows;
      } catch (_) {
        continue;
      }
    }
    if (best == null) return null;

    int columnIndex(String letters) {
      var acc = 0;
      for (final code in letters.toUpperCase().codeUnits) {
        acc = acc * 26 + (code - 64);
      }
      return acc - 1;
    }

    var width = 0;
    for (final row in best) {
      for (final letters in row.keys) {
        final i = columnIndex(letters) + 1;
        if (i > width) width = i;
      }
    }
    return best.map((row) {
      final cells = List<String>.filled(width, '');
      row.forEach((letters, value) {
        final i = columnIndex(letters);
        if (i >= 0 && i < width) cells[i] = value.trim();
      });
      return cells;
    }).toList();
  }

  static List<List<String>> _densifyXls(Map<int, Map<int, String>> grid) {
    var width = 0;
    for (final row in grid.values) {
      for (final col in row.keys) {
        if (col + 1 > width) width = col + 1;
      }
    }
    final rowKeys = grid.keys.toList()..sort();
    return rowKeys.map((rowIndex) {
      final cells = List<String>.filled(width, '');
      (grid[rowIndex] ?? {}).forEach((col, value) {
        if (col >= 0 && col < width) cells[col] = value.trim();
      });
      return cells;
    }).toList();
  }
}
