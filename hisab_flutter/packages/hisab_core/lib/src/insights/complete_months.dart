/// Which months a statement covers end to end. Port of CompleteMonths.swift.
library;

import '../domain.dart';
import '../year_month.dart';

class CompleteMonths {
  static Set<YearMonth> of(List<DatePeriod> periods) {
    final result = <YearMonth>{};
    for (final period in periods) {
      for (final month in period.months) {
        final (start, end) = bounds(month);
        if (!period.start.isAfter(start) && !period.end.isBefore(end)) {
          result.add(month);
        }
      }
    }
    return result;
  }

  /// Newest complete month that isn't in the future.
  static YearMonth? latest(List<DatePeriod> periods, DateTime now) {
    final cap = YearMonth.fromDate(now);
    final eligible = [
      for (final m in of(periods))
        if (m.compareTo(cap) <= 0) m
    ]..sort();
    return eligible.isEmpty ? null : eligible.last;
  }

  /// First instant of the month and its last second, both in IST, expressed
  /// as UTC instants (IST midnight is UTC 18:30 the previous day).
  static (DateTime, DateTime) bounds(YearMonth month) {
    final start = DateTime.utc(month.year, month.month, 1).subtract(istOffset);
    final next = month.advancedBy(1);
    final end = DateTime.utc(next.year, next.month, 1)
        .subtract(istOffset)
        .subtract(const Duration(seconds: 1));
    return (start, end);
  }
}
