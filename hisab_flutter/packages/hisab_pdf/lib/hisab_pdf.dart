/// PDF statement parsers for Hisab, plus the hooks that give hisab_core's
/// generic engine PDF table extraction. Flutter-only (Syncfusion needs
/// dart:ui); everything else lives in the pure-Dart hisab_core.
library;

import 'package:hisab_core/hisab_core.dart' as core;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'src/bhim_pdf_parser.dart';
import 'src/gpay_pdf_parser.dart';
import 'src/hdfc_pdf_parser.dart';
import 'src/paytm_pdf_parser.dart';
import 'src/pdf_text.dart';

export 'src/bhim_pdf_parser.dart';
export 'src/gpay_pdf_parser.dart';
export 'src/hdfc_pdf_parser.dart';
export 'src/paytm_pdf_parser.dart';
export 'src/pdf_text.dart';

/// The PDF parser set appended to hisab_core's liveRegistry.
/// (IDFC PDF is deliberately absent: Syncfusion drops glyphs in that
/// statement's embedded font, silently corrupting rail references. IDFC's
/// XLSX rendition of the same statement parses perfectly — the unsupported
/// sheet steers users there.)
List<core.StatementParser> pdfParsers() => const [
      GpayPdfParser(),
      PaytmPdfParser(),
      BhimPdfParser(),
      HdfcPdfParser(),
    ];

/// Wires hisab_core's injectable PDF hooks (generic-engine table extraction
/// and the locked-PDF check). Call once at app start.
void installPdfHooks() {
  core.pdfIsLockedCheck = PdfText.isLocked;
  core.pdfLinesExtractor = (data, password) {
    PdfDocument? doc;
    try {
      doc = PdfText.open(data, password);
    } catch (_) {
      return null;
    }
    if (doc == null) return null;
    try {
      final rows = <List<String>>[];
      for (var page = 0; page < doc.pages.count; page++) {
        for (final line in PdfText.pageLines(doc, page)) {
          // Split a visual line into cells on horizontal gaps.
          final cells = <String>[];
          final current = StringBuffer();
          double? lastRight;
          for (final word in line.words) {
            if (lastRight != null && word.x - lastRight > 7) {
              if (current.isNotEmpty) cells.add(current.toString());
              current.clear();
            }
            if (current.isNotEmpty) current.write(' ');
            current.write(word.text);
            lastRight = word.x + word.width;
          }
          if (current.isNotEmpty) cells.add(current.toString());
          if (cells.isNotEmpty) rows.add(cells);
        }
      }
      return rows;
    } finally {
      doc.dispose();
    }
  };
}

/// The complete live registry for the app: code parsers + PDF parsers.
core.ParserRegistry fullRegistry() => core.liveRegistry(extra: pdfParsers());
