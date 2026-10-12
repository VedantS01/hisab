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
  core.pdfFragmentsExtractor = (data, password) {
    PdfDocument? doc;
    try {
      doc = PdfText.open(data, password);
    } catch (_) {
      return null;
    }
    if (doc == null) return null;
    try {
      if (_isIdfcStatement(doc)) return null;
      return [for (var page = 0; page < doc.pages.count; page++) PdfText.pageFragments(doc, page)];
    } finally {
      doc.dispose();
    }
  };
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

/// IDFC FIRST's statement font loses glyphs in Syncfusion — "UPI/D/60643614627"
/// for "UPI/DR/606435614627": the amounts survive, the narrations and the rail
/// references inside them don't. The XLSX of the same statement reads exactly
/// (IdfcXlsxParser), so the layout reader leaves these PDFs alone and the
/// format sheet steers to the XLSX, as before. Identified by the branch IFSC in
/// page 1's account block — the glyph loss eats "IFSC" itself down to "IFS",
/// and an IDFC IFSC in another bank's narration sits further down the page.
bool _isIdfcStatement(PdfDocument doc) {
  final accountBlock = PdfText.pageLines(doc, 0).take(30).map((l) => l.text).join('\n');
  return RegExp(r'\bIFSC?\s*:\s*IDFB0').hasMatch(accountBlock);
}

/// The complete live registry for the app: code parsers + PDF parsers.
core.ParserRegistry fullRegistry() => core.liveRegistry(extra: pdfParsers());
