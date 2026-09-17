/// Minimal .xlsx reader over the archive + xml packages: shared strings plus
/// per-sheet rows as {columnLetter: cellText}. Port of XLSXReader.swift.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxWorkbook {
  final List<String> sharedStrings;
  final Map<String, List<Map<String, String>>> sheets; // entry name -> rows
  const XlsxWorkbook({required this.sharedStrings, required this.sheets});
}

class XlsxReader {
  /// Null when the bytes are not a readable xlsx.
  static XlsxWorkbook? read(List<int> data) {
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(data);
    } catch (_) {
      return null;
    }

    final shared = <String>[];
    for (final file in archive.files) {
      if (file.name != 'xl/sharedStrings.xml') continue;
      try {
        final doc =
            XmlDocument.parse(utf8.decode(file.content as List<int>));
        for (final si in doc.findAllElements('si')) {
          shared.add(si.findAllElements('t').map((t) => t.innerText).join());
        }
      } catch (_) {
        return null;
      }
    }

    final sheets = <String, List<Map<String, String>>>{};
    for (final file in archive.files) {
      if (!file.name.startsWith('xl/worksheets/') ||
          !file.name.endsWith('.xml')) {
        continue;
      }
      try {
        final doc =
            XmlDocument.parse(utf8.decode(file.content as List<int>));
        final rows = <Map<String, String>>[];
        for (final row in doc.findAllElements('row')) {
          final cells = <String, String>{};
          for (final c in row.findAllElements('c')) {
            final ref = c.getAttribute('r') ?? '';
            final letters = ref
                .split('')
                .takeWhile((ch) => RegExp(r'[A-Za-z]').hasMatch(ch))
                .join();
            final type = c.getAttribute('t') ?? '';
            final v = c.getElement('v')?.innerText ??
                c
                    .getElement('is')
                    ?.findAllElements('t')
                    .map((t) => t.innerText)
                    .join() ??
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
        sheets[file.name] = rows;
      } catch (_) {
        continue;
      }
    }
    return XlsxWorkbook(sharedStrings: shared, sheets: sheets);
  }

  static int columnIndex(String letters) {
    var acc = 0;
    for (final code in letters.toUpperCase().codeUnits) {
      acc = acc * 26 + (code - 64);
    }
    return acc - 1;
  }
}
