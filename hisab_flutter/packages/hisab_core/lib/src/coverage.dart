/// Month × source coverage grid. Port of Coverage.swift.
library;

import 'domain.dart';
import 'year_month.dart';

class DocumentSummary {
  final String id;
  final Source source;
  final DatePeriod period;
  const DocumentSummary(
      {required this.id, required this.source, required this.period});
}

sealed class CellState {
  const CellState();
}

class CellPresent extends CellState {
  final List<String> documentIDs;
  const CellPresent(this.documentIDs);
}

class CellAwaiting extends CellState {
  const CellAwaiting();
}

/// Months are derived, never stored: the union of every document's covered
/// months and manual pins, gap-filled so interior holes stay visible.
class CoverageGrid {
  final List<YearMonth> months; // newest first
  /// Sources actually observed in the input documents: payment apps first,
  /// then banks, alphabetical within kind.
  final List<Source> sources;
  final Map<YearMonth, Map<Source, List<String>>> _cells;

  CoverageGrid._(this.months, this.sources, this._cells);

  CellState state(YearMonth month, Source source) {
    final ids = _cells[month]?[source];
    if (ids != null && ids.isNotEmpty) return CellPresent(ids);
    return const CellAwaiting();
  }

  static CoverageGrid derive({
    required List<DocumentSummary> documents,
    required Set<YearMonth> pinnedMonths,
  }) {
    final cells = <YearMonth, Map<Source, List<String>>>{};
    final touched = Set<YearMonth>.from(pinnedMonths);
    for (final doc in documents) {
      for (final month in doc.period.months) {
        touched.add(month);
        cells.putIfAbsent(month, () => {})
            .putIfAbsent(doc.source, () => [])
            .add(doc.id);
      }
    }
    final sources = Source.ordered(documents.map((d) => d.source));
    if (touched.isEmpty) return CoverageGrid._([], sources, {});
    final sorted = touched.toList()..sort();
    final months = YearMonth.monthsFromThrough(sorted.first, sorted.last)
        .reversed
        .toList();
    return CoverageGrid._(months, sources, cells);
  }
}
