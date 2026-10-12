/// Rebuilds a bank statement's transaction table from positioned text. Port of
/// StatementLayout.swift; the PDF adapter (hisab_pdf) supplies the fragments.
library;

import 'dart:math' as math;

import '../money.dart';
import 'normalized_table.dart';

/// A run of text at a position on a PDF page, in PDF user space (y grows up —
/// the adapter flips Syncfusion's top-left origin so both platforms share one
/// geometry and one set of fixtures).
class TextFragment {
  final String text;
  final double minX, maxX, minY, maxY;
  const TextFragment(
      {required this.text,
      required this.minX,
      required this.maxX,
      required this.minY,
      required this.maxY});

  double get midX => (minX + maxX) / 2;
  double get midY => (minY + maxY) / 2;
  double get height => maxY - minY;
}

enum LayoutRole { date, narration, reference, debit, credit, amount, balance }

class _Column {
  final String label;
  final LayoutRole? role;
  final double minX, maxX;
  const _Column(this.label, this.role, this.minX, this.maxX);
  double get midX => (minX + maxX) / 2;
}

/// The column header names the columns and fixes their x positions; a
/// parseable date in the leftmost date column starts a row; every other cell
/// joins the row it vertically surrounds. Anything that belongs to no row —
/// the account block, an opening-balance line, page footers — is left out.
/// Nothing here decides what the numbers mean: the result is a plain table
/// for `ColumnInference` (or a model's proposal) and the balance chain to
/// accept or refuse.
class StatementLayout {
  /// Null when no page has a header naming a date, a balance and an amount
  /// (separate debit and credit columns, or one amount column).
  static NormalizedTable? table(List<List<TextFragment>> pages) {
    List<_Column>? columns;
    final rows = <List<String>>[];
    final centred = _Flag();
    final cleanPages = [
      for (final page in pages) page.where((f) => f.text.trim().isNotEmpty).toList()
    ];
    // Text printed at the same spot on more than one page: a repeated account
    // block ("To : 31/03/2026"), a footer.
    final pagesWith = <String, int>{};
    for (final page in cleanPages) {
      for (final key in page.map(_spot).toSet()) {
        pagesWith[key] = (pagesWith[key] ?? 0) + 1;
      }
    }
    final furniture = {
      for (final e in pagesWith.entries)
        if (e.value > 1) e.key
    };
    for (final cleaned in cleanPages) {
      var body = cleaned;
      final header = _findHeader(cleaned);
      if (header != null) {
        columns = header.columns;
        body = cleaned.where((f) => f.maxY < header.bottom).toList();
      }
      final cols = columns;
      if (cols == null) continue;
      final page = _readRows(body, cols, furniture, centred);
      // Narration that spilled over the page break belongs to the last row of
      // the previous page.
      final narration = cols.indexWhere((c) => c.role == LayoutRole.narration);
      if (page.spill != null && rows.isNotEmpty && narration >= 0) {
        rows.last[narration] = _join(rows.last[narration], page.spill!);
      }
      rows.addAll(page.rows);
    }
    final cols = columns;
    if (cols == null || rows.isEmpty) return null;
    return NormalizedTable(
        rows: [cols.map((c) => c.label).toList(), ...rows], container: 'pdf');
  }

  // MARK: header

  static LayoutRole? roleOf(String label) {
    final l = label.toLowerCase();
    bool has(String pattern) => RegExp(pattern).hasMatch(l);
    if (has(r'\bbalance\b|\bbal\b')) return LayoutRole.balance;
    if (has(r'withdraw|\bdebit|\bdr\b|paid out')) return LayoutRole.debit;
    if (has(r'deposit|\bcredit|\bcr\b|paid in')) return LayoutRole.credit;
    if (has(r'\bdate\b|\bdt\b')) return LayoutRole.date;
    if (has(r'particular|narration|description|details|remark')) {
      return LayoutRole.narration;
    }
    if (has(r'cheque|\bchq|\bref|instrument')) return LayoutRole.reference;
    if (has(r'\bamount\b|\bamt\b')) return LayoutRole.amount;
    return null;
  }

  /// Lines of up to three stacked header rows, merged into labelled columns.
  /// The band naming the most roles wins, then the one with the most labelled
  /// columns, then the one with the fewest lines (the topmost on a full tie).
  static ({List<_Column> columns, double bottom})? _findHeader(
      List<TextFragment> fragments) {
    final lines = _groupLines(fragments);
    List<_Column>? bestColumns;
    double? bestBottom;
    List<int>? bestScore;
    for (var start = 0; start < lines.length; start++) {
      for (var count = 1; count <= 3 && start + count <= lines.length; count++) {
        final band = lines.sublist(start, start + count);
        // Stacked header rows sit within ~2.5 line heights.
        if (band.first.first.maxY - band.last.first.minY >= 30) break;
        final all = band.expand((l) => l).toList();
        final columns = _mergeColumns(all);
        final roles = columns.map((c) => c.role).whereType<LayoutRole>().toSet();
        final hasAmount = roles.contains(LayoutRole.amount) ||
            (roles.contains(LayoutRole.debit) && roles.contains(LayoutRole.credit));
        if (!roles.contains(LayoutRole.date) ||
            !roles.contains(LayoutRole.balance) ||
            !hasAmount) {
          continue;
        }
        final score = [
          roles.length,
          columns.where((c) => c.role != null).length,
          -count
        ];
        if (bestScore != null && _compare(score, bestScore) <= 0) continue;
        bestColumns = columns;
        bestBottom = all.map((f) => f.minY).reduce(math.min) - 0.5;
        bestScore = score;
      }
    }
    return bestColumns == null
        ? null
        : (columns: bestColumns, bottom: bestBottom!);
  }

  static int _compare(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return 0;
  }

  /// Fragments that overlap horizontally across stacked header lines are one
  /// label ("Transaction" over "Date", "Cheque" over "No").
  static List<_Column> _mergeColumns(List<TextFragment> fragments) {
    final groups = <(double, double, List<TextFragment>)>[];
    for (final f in [...fragments]..sort((a, b) => a.minX.compareTo(b.minX))) {
      final i = groups.indexWhere((g) => f.minX < g.$2 && f.maxX > g.$1);
      if (i >= 0) {
        final g = groups[i];
        groups[i] = (math.min(g.$1, f.minX), math.max(g.$2, f.maxX), [...g.$3, f]);
      } else {
        groups.add((f.minX, f.maxX, [f]));
      }
    }
    final columns = groups.map((g) {
      final parts = [...g.$3]..sort((a, b) => b.maxY.compareTo(a.maxY));
      final label = parts.map((p) => p.text.trim()).join(' ');
      return _Column(label, roleOf(label), g.$1, g.$2);
    }).toList()
      ..sort((a, b) => a.midX.compareTo(b.midX));
    return columns;
  }

  /// Fragments on the same baseline (within 2pt), top line first.
  static List<List<TextFragment>> _groupLines(List<TextFragment> fragments) {
    final lines = <List<TextFragment>>[];
    for (final f in [...fragments]..sort((a, b) => b.midY.compareTo(a.midY))) {
      if (lines.isNotEmpty && (lines.last.first.midY - f.midY).abs() < 2) {
        lines.last.add(f);
      } else {
        lines.add([f]);
      }
    }
    return lines;
  }

  // MARK: rows

  /// The nearest header centre — good enough to find the dates, which sit
  /// under their header; not for text, whose header is often centred over
  /// left-aligned cells.
  static int _nearestColumn(double x, List<_Column> columns) {
    var best = 0;
    for (var i = 0; i < columns.length; i++) {
      if ((columns[i].midX - x).abs() < (columns[best].midX - x).abs()) best = i;
    }
    return best;
  }

  static bool _fits(TextFragment f, LayoutRole? role) => switch (role) {
        LayoutRole.date => DateShapes.looksLikeDate(f.text),
        LayoutRole.debit ||
        LayoutRole.credit ||
        LayoutRole.amount ||
        LayoutRole.balance =>
          _isNumber(f),
        _ => false,
      };

  static bool _isNumber(TextFragment f) => Money.signedPaise(f.text) != null;

  /// Where each column ends, read off the dated lines. Dates and amounts sit
  /// under their own header, so they mark exactly where a date or amount
  /// column runs; a text column's header is often centred over left-aligned
  /// cells, so its edge is the whitespace next to its typed neighbour — or,
  /// between two text columns, the widest strip no text covers. The midpoint
  /// of the header centres when text bridges the gap.
  static List<double> _boundaries(List<_Column> columns, List<TextFragment> lines) {
    final extents = List<(double, double)?>.filled(columns.length, null);
    for (final f in lines) {
      final c = _nearestColumn(f.midX, columns);
      if (!_fits(f, columns[c].role)) continue;
      final e = extents[c];
      extents[c] = e == null
          ? (f.minX, f.maxX)
          : (math.min(e.$1, f.minX), math.max(e.$2, f.maxX));
    }
    final covered = <(double, double)>[];
    for (final f in [...lines]..sort((a, b) => a.minX.compareTo(b.minX))) {
      if (covered.isNotEmpty && f.minX <= covered.last.$2) {
        covered.last = (covered.last.$1, math.max(covered.last.$2, f.maxX));
      } else {
        covered.add((f.minX, f.maxX));
      }
    }
    List<(double, double)> gaps(double a, double b) {
      if (a >= b) return const [];
      final result = <(double, double)>[];
      var x = a;
      for (final span in covered) {
        if (span.$2 <= x || span.$1 >= b) continue;
        if (span.$1 > x) result.add((x, span.$1));
        x = math.max(x, span.$2);
      }
      if (x < b) result.add((x, b));
      return result;
    }

    double? mid((double, double)? gap) =>
        gap == null ? null : (gap.$1 + gap.$2) / 2;

    return [
      for (var i = 0; i < columns.length - 1; i++)
        () {
          final left = columns[i], right = columns[i + 1];
          final fallback = (left.midX + right.midX) / 2;
          final l = extents[i], r = extents[i + 1];
          if (l != null && r != null) {
            return l.$2 < r.$1 ? (l.$2 + r.$1) / 2 : fallback;
          }
          if (l != null) return mid(gaps(l.$2, right.midX).firstOrNull) ?? l.$2;
          if (r != null) return mid(gaps(left.midX, r.$1).lastOrNull) ?? r.$1;
          final all = gaps(left.midX, right.midX);
          if (all.isEmpty) return fallback;
          return mid(all.reduce(
              (a, b) => (b.$2 - b.$1) > (a.$2 - a.$1) ? b : a))!;
        }()
    ];
  }

  /// [centred] carries across pages: once a row's narration is seen starting
  /// above its date, text above a page's first date is that row's too.
  static ({List<List<String>> rows, String? spill}) _readRows(
      List<TextFragment> fragments,
      List<_Column> columns,
      Set<String> furniture,
      _Flag centred) {
    const none = (rows: <List<String>>[], spill: null);
    final dateColumn = columns.indexWhere((c) => c.role == LayoutRole.date);
    if (dateColumn < 0) return none;

    // A row starts at every date in the leftmost date column.
    final anchors = fragments
        .where((f) =>
            DateShapes.looksLikeDate(f.text) &&
            _nearestColumn(f.midX, columns) == dateColumn)
        .toList()
      ..sort((a, b) => b.midY.compareTo(a.midY));
    if (anchors.isEmpty) return none;
    final lineHeight = _median(fragments.map((f) => f.height)) ?? 10;

    final dated = fragments
        .where((f) => anchors.any((a) => (a.midY - f.midY).abs() < lineHeight / 2))
        .toList();
    final edges = _boundaries(columns, dated);
    final byColumn = List.generate(columns.length, (_) => <TextFragment>[]);
    for (final f in fragments) {
      // Numbers and dates are placed by their middle (amounts are
      // right-aligned), text by where it starts (it is left-aligned).
      final x = _isNumber(f) || DateShapes.looksLikeDate(f.text) ? f.midX : f.minX + 1;
      final i = edges.indexWhere((e) => x < e);
      byColumn[i < 0 ? edges.length : i].add(f);
    }

    // Rows are separated by every date and by every amount on no date's line
    // (an opening balance, a carried-forward total), which closes the row
    // above without starting one.
    final numeric = [
      for (var i = 0; i < columns.length; i++)
        if (const [
          LayoutRole.debit,
          LayoutRole.credit,
          LayoutRole.amount,
          LayoutRole.balance
        ].contains(columns[i].role))
          i
    ];
    final separators = <(double, int?)>[
      for (var i = 0; i < anchors.length; i++) (anchors[i].midY, i)
    ];
    for (final f in numeric.expand((c) => byColumn[c])) {
      if (_isNumber(f) &&
          !anchors.any((a) => a.minY < f.maxY && f.minY < a.maxY) &&
          !separators.any((s) => (s.$1 - f.midY).abs() < 2)) {
        separators.add((f.midY, null));
      }
    }
    separators.sort((a, b) => b.$1.compareTo(a.$1));

    // Each row's vertical extent: its date, widened by its narration lines.
    final tops = [for (final a in anchors) a.maxY];
    final bottoms = [for (final a in anchors) a.minY];
    final spill = <TextFragment>[];
    final narrationColumn = columns.indexWhere((c) => c.role == LayoutRole.narration);
    if (narrationColumn >= 0) {
      final lines = _groupLines(byColumn[narrationColumn]);
      final ys = [
        for (final line in lines)
          line.map((f) => f.midY).reduce((a, b) => a + b) / line.length
      ];
      final pitch = _median([for (var i = 0; i + 1 < ys.length; i++) ys[i] - ys[i + 1]]) ??
          lineHeight * 1.5;
      final owner = List<int?>.filled(lines.length, null); // index into separators
      final above = <int>[], below = <int>[];
      for (var i = 0; i < ys.length; i++) {
        final s = separators.indexWhere((s) => (s.$1 - ys[i]).abs() < 2);
        if (s >= 0) {
          owner[i] = s;
          continue;
        }
        final lower = separators.indexWhere((s) => s.$1 < ys[i]);
        if (lower == 0) {
          above.add(i);
        } else if (lower < 0) {
          below.add(i);
        }
      }
      // Lines between two separators split at the widest gap: IDFC centres a
      // multi-line narration on its date, so its first lines sit above it;
      // HDFC hangs it below at the same pitch as the rows themselves, so a tie
      // goes to the lowest gap.
      for (var s = 1; s < separators.length; s++) {
        final between = [
          for (var i = 0; i < ys.length; i++)
            if (owner[i] == null &&
                ys[i] < separators[s - 1].$1 &&
                ys[i] > separators[s].$1)
              i
        ];
        final points = [separators[s - 1].$1, for (final i in between) ys[i], separators[s].$1];
        var split = 0;
        var widest = double.negativeInfinity;
        for (var g = 0; g + 1 < points.length; g++) {
          if (points[g] - points[g + 1] >= widest - 0.5) {
            split = g;
            widest = math.max(widest, points[g] - points[g + 1]);
          }
        }
        for (var k = 0; k < between.length; k++) {
          owner[between[k]] = k < split ? s - 1 : s;
          if (k >= split && separators[s].$2 != null) centred.value = true;
        }
      }
      // Past the first and last separators, only lines that keep the pitch
      // belong to the table, up to the first piece of page furniture; the
      // account block and footers don't.
      bool keepsOn(int i, double y) =>
          (y - ys[i]).abs() <= pitch * 2 &&
          !lines[i].any((f) => furniture.contains(_spot(f)));
      var y = separators.last.$1;
      for (final i in below) {
        if (!keepsOn(i, y)) break;
        owner[i] = separators.length - 1;
        y = ys[i];
      }
      // Hanging narration above the first date is the previous page's row
      // running on. Centred narration is this row's, up to a gap wider than
      // the line pitch — the padding between two rows — and the previous
      // page's row again above that.
      y = separators.first.$1;
      var spilling = !centred.value;
      for (final i in above.reversed) {
        if (!keepsOn(i, y)) break;
        if (ys[i] - y > pitch * 1.25) spilling = true;
        if (spilling) {
          spill.addAll(lines[i]);
        } else {
          owner[i] = 0;
        }
        y = ys[i];
      }
      for (var i = 0; i < lines.length; i++) {
        final s = owner[i];
        final row = s == null ? null : separators[s].$2;
        if (row == null) continue;
        tops[row] = math.max(tops[row], lines[i].map((f) => f.maxY).reduce(math.max));
        bottoms[row] = math.min(bottoms[row], lines[i].map((f) => f.minY).reduce(math.min));
      }
    }

    final rows = [
      for (var row = 0; row < anchors.length; row++)
        [
          for (final columnFragments in byColumn)
            _text(columnFragments
                .where((f) => f.midY <= tops[row] + 1 && f.midY >= bottoms[row] - 1)
                .toList())
        ]
    ];
    // Rows can overlap only by a broken layout; a fragment claimed twice would
    // double an amount, so such a page yields nothing rather than a guess.
    for (var row = 1; row < anchors.length; row++) {
      if (tops[row] > bottoms[row - 1] + 1) return none;
    }
    // A date with no amount and no balance beside it is not a transaction (a
    // period line in a repeated account block, say).
    return (
      rows: rows.where((r) => numeric.any((c) => r[c].isNotEmpty)).toList(),
      spill: spill.isEmpty ? null : _text(spill),
    );
  }

  static String _spot(TextFragment f) =>
      '${f.minX.round()} ${f.minY.round()} ${f.text.trim()}';

  /// Top to bottom, left to right, single-spaced.
  static String _text(List<TextFragment> fragments) {
    final sorted = [...fragments]..sort((a, b) => (a.midY - b.midY).abs() > 2
        ? b.midY.compareTo(a.midY)
        : a.minX.compareTo(b.minX));
    return sorted.map((f) => f.text.trim()).join(' ');
  }

  static String _join(String a, String b) =>
      a.isEmpty ? b : (b.isEmpty ? a : '$a $b');

  static double? _median(Iterable<double> values) {
    final sorted = values.where((v) => v > 0).toList()..sort();
    return sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
  }
}

class _Flag {
  bool value = false;
}

/// Whether a cell reads as a calendar date in any of the shapes Indian bank
/// statements print. Only a gate for row anchors: `ColumnInference` decides
/// the actual format from the whole column.
class DateShapes {
  static final _pattern = RegExp(
      r"^(\d{1,2}[-/. ](\d{1,2}|[A-Za-z]{3,9})[-/. ,']*\d{2,4}|\d{4}-\d{2}-\d{2}|[A-Za-z]{3,9} \d{1,2},? \d{4})$");

  static bool looksLikeDate(String text) => _pattern.hasMatch(text.trim());
}
