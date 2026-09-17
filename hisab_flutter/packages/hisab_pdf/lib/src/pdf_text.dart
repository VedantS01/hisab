/// PDF text extraction over syncfusion_flutter_pdf: per-page text lines in
/// visual order (top→bottom, left→right), with word bounds for geometric
/// parsers. The Android-side counterpart of PDFKit's text layer.
library;

import 'package:syncfusion_flutter_pdf/pdf.dart';

class PdfWordBox {
  final String text;
  final double x, y, width, height;
  const PdfWordBox(this.text, this.x, this.y, this.width, this.height);
}

class PdfLineBox {
  final String text;
  final double y;
  final List<PdfWordBox> words;
  const PdfLineBox(this.text, this.y, this.words);
}

class PdfText {
  /// Null when not a PDF; throws [PdfPasswordException] when locked and the
  /// password is missing/wrong.
  static PdfDocument? open(List<int> data, String? password) {
    if (data.length < 4 || String.fromCharCodes(data.take(4)) != '%PDF') {
      return null;
    }
    try {
      return PdfDocument(inputBytes: data, password: password);
    } catch (e) {
      if (e.toString().toLowerCase().contains('password')) {
        rethrow;
      }
      return null;
    }
  }

  static bool isLocked(List<int> data, String? password) {
    if (data.length < 4 || String.fromCharCodes(data.take(4)) != '%PDF') {
      return false;
    }
    try {
      final doc = PdfDocument(inputBytes: data, password: password);
      doc.dispose();
      return false;
    } catch (e) {
      return e.toString().toLowerCase().contains('password');
    }
  }

  /// Page texts, each as newline-joined visual lines.
  static List<String>? pageTexts(List<int> data, String? password) {
    final doc = open(data, password);
    if (doc == null) return null;
    try {
      final pages = <String>[];
      for (var i = 0; i < doc.pages.count; i++) {
        final lines = pageLines(doc, i);
        pages.add(lines.map((l) => l.text).join('\n'));
      }
      return pages;
    } finally {
      doc.dispose();
    }
  }

  /// Visual lines for one page. Syncfusion may split one visual row into
  /// several TextLines (one per column block), so TextLines are merged when
  /// their tops sit within a tight 2pt band — never looser, or dense bank
  /// tables chain-merge adjacent rows.
  static List<PdfLineBox> pageLines(PdfDocument doc, int pageIndex) {
    final extractor = PdfTextExtractor(doc);
    final textLines = extractor.extractTextLines(
        startPageIndex: pageIndex, endPageIndex: pageIndex);
    final fragments = <(double, List<PdfWordBox>)>[];
    for (final line in textLines) {
      final words = <PdfWordBox>[];
      for (final word in line.wordCollection) {
        final b = word.bounds;
        final text = word.text.trim();
        if (text.isEmpty) continue;
        words.add(PdfWordBox(text, b.left, b.top, b.width, b.height));
      }
      if (words.isNotEmpty) fragments.add((line.bounds.top, words));
    }
    fragments.sort((a, b) => a.$1.compareTo(b.$1));

    final lines = <(double, List<PdfWordBox>)>[];
    for (final (top, words) in fragments) {
      var merged = false;
      if (lines.isNotEmpty) {
        final delta = (top - lines.last.$1).abs();
        if (delta <= 2.0) {
          merged = true;
        } else if (delta <= 6.0) {
          // A slightly offset fragment of the same visual row never overlaps
          // the row horizontally; a genuinely new table row always does.
          final existing = lines.last.$2;
          merged = words.every((w) => existing.every((e) =>
              w.x + w.width <= e.x || e.x + e.width <= w.x));
        }
      }
      if (merged) {
        lines.last.$2.addAll(words);
      } else {
        lines.add((top, List.of(words)));
      }
    }
    return lines.map((entry) {
      final ws = entry.$2..sort((a, b) => a.x.compareTo(b.x));
      return PdfLineBox(ws.map((w) => w.text).join(' '), entry.$1, ws);
    }).toList();
  }
}
