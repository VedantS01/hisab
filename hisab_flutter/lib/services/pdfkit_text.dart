/// iOS reads statement PDFs with PDFKit (ios/Runner/PdfKitText.swift), as the
/// Swift app did, instead of Syncfusion — which drops glyphs in some embedded
/// fonts and corrupted IDFC FIRST's references badly enough that IDFC PDFs
/// had to be refused.
///
/// hisab_core's PDF hooks are synchronous and the platform channel is not, so
/// the import reads the file ahead of the parse ([prepare]); the hooks then
/// find that reading by the file's bytes ([fragments], [lines]) and fall back
/// to Syncfusion for anything else. IDFC PDFs, which Syncfusion can't read,
/// get their parser here ([parsers]).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hisab_core/hisab_core.dart';

abstract final class PdfKitText {
  static const _channel = MethodChannel('hisab/pdfkit');

  static (int, List<List<TextFragment>>, List<List<String>>)? _ready;

  static bool get available => !kIsWeb && Platform.isIOS;

  /// Parsers that need PDFKit's reading, for the app's registry.
  static List<StatementParser> get parsers =>
      available ? const [IdfcPdfParser(fragments)] : const [];

  /// Puts PDFKit's reading ahead of the Syncfusion hooks [installPdfHooks]
  /// set. Call after it.
  static void install() {
    if (!available) return;
    final syncfusionFragments = pdfFragmentsExtractor;
    final syncfusionLines = pdfLinesExtractor;
    pdfFragmentsExtractor =
        (data, password) => fragments(data) ?? syncfusionFragments?.call(data, password);
    pdfLinesExtractor =
        (data, password) => lines(data) ?? syncfusionLines?.call(data, password);
  }

  /// Reads [data] with PDFKit when it is a PDF and this is iOS; afterwards the
  /// hooks serve that reading for these bytes. Anything else clears it.
  static Future<void> prepare(List<int> data, String? password) async {
    _ready = null;
    if (!available || !_isPdf(data)) return;
    final List<Object?>? raw;
    try {
      raw = await _channel.invokeListMethod<Object?>('pages', {
        'data': data is Uint8List ? data : Uint8List.fromList(data),
        'password': password,
      });
    } on PlatformException {
      return;
    }
    if (raw == null) return;
    final pages = [
      for (final page in raw)
        [for (final run in page as List) Map<String, Object?>.from(run as Map)]
    ];
    _ready = (
      _key(data),
      [for (final page in pages) [for (final run in page) ...split(run)]],
      [for (final page in pages) for (final run in page) ...cells(run)],
    );
  }

  static List<List<TextFragment>>? fragments(List<int> data) {
    final ready = _ready;
    return ready != null && ready.$1 == _key(data) ? ready.$2 : null;
  }

  static List<List<String>>? lines(List<int> data) {
    final ready = _ready;
    return ready != null && ready.$1 == _key(data) ? ready.$3 : null;
  }

  /// One line run as table fragments. PDFKit joins neighbouring runs on a
  /// line when the gap is narrow, so a long narration can swallow the amount
  /// beside it ("…/06:23:34 5,97,803.00"). A run holding a number or a date is
  /// cut wherever two words sit further apart than half the line height.
  /// Port of the Swift app's NormalizedTable.split.
  @visibleForTesting
  static List<TextFragment> split(Map<String, Object?> run) {
    final minY = (run['y0'] as num).toDouble();
    final maxY = (run['y1'] as num).toDouble();
    final whole = TextFragment(
        text: run['t'] as String,
        minX: (run['x0'] as num).toDouble(),
        maxX: (run['x1'] as num).toDouble(),
        minY: minY,
        maxY: maxY);
    final words = [
      for (final w in run['words'] as List? ?? const [])
        Map<String, Object?>.from(w as Map)
    ];
    if (words.length < 2 ||
        !words.any((w) =>
            Money.signedPaise(w['t'] as String) != null ||
            DateShapes.looksLikeDate(w['t'] as String))) {
      return [whole];
    }
    final gap = (maxY - minY) / 2;
    final pieces = <(String, double, double)>[];
    for (final w in words) {
      final text = w['t'] as String;
      final x0 = (w['x0'] as num).toDouble();
      final x1 = (w['x1'] as num).toDouble();
      if (pieces.isNotEmpty && x0 - pieces.last.$3 <= gap) {
        final last = pieces.removeLast();
        pieces.add(('${last.$1} $text', last.$2, x1 > last.$3 ? x1 : last.$3));
      } else {
        pieces.add((text, x0, x1));
      }
    }
    return [
      for (final (text, x0, x1) in pieces)
        TextFragment(text: text, minX: x0, maxX: x1, minY: minY, maxY: maxY)
    ];
  }

  /// One line run as cells, cut on horizontal gaps — the plain-lines fallback
  /// the Syncfusion adapter also provides.
  @visibleForTesting
  static List<List<String>> cells(Map<String, Object?> run) {
    final words = [
      for (final w in run['words'] as List? ?? const [])
        Map<String, Object?>.from(w as Map)
    ];
    if (words.isEmpty) {
      final text = (run['t'] as String).trim();
      return text.isEmpty ? const [] : [[text]];
    }
    final cells = <String>[];
    final current = StringBuffer();
    double? lastRight;
    for (final w in words) {
      final x0 = (w['x0'] as num).toDouble();
      if (lastRight != null && x0 - lastRight > 7 && current.isNotEmpty) {
        cells.add(current.toString());
        current.clear();
      }
      if (current.isNotEmpty) current.write(' ');
      current.write(w['t']);
      lastRight = (w['x1'] as num).toDouble();
    }
    if (current.isNotEmpty) cells.add(current.toString());
    return [cells];
  }

  static bool _isPdf(List<int> data) =>
      data.length > 4 &&
      data[0] == 0x25 && data[1] == 0x50 && data[2] == 0x44 && data[3] == 0x46;

  /// Cheap identity for the bytes in hand: length plus their ends.
  static int _key(List<int> data) {
    const span = 1024;
    final head = data.length < span ? data : data.sublist(0, span);
    final tail = data.length < span ? const <int>[] : data.sublist(data.length - span);
    return Object.hash(data.length, Object.hashAll(head), Object.hashAll(tail));
  }
}
