/// A calendar month, resolved in Indian Standard Time.
///
/// IST is a fixed UTC+05:30 offset with no DST, so all IST calendar math is
/// done by shifting UTC instants — no timezone database needed.
library;

const Duration istOffset = Duration(hours: 5, minutes: 30);

/// The instant shifted so its UTC fields read as IST wall-clock fields.
DateTime istClock(DateTime date) => date.toUtc().add(istOffset);

/// "yyyy-MM-dd" of the instant in IST — the day key used in content hashes
/// and synthetic references.
String istDayString(DateTime date) {
  final c = istClock(date);
  return '${c.year.toString().padLeft(4, '0')}-'
      '${c.month.toString().padLeft(2, '0')}-'
      '${c.day.toString().padLeft(2, '0')}';
}

/// "yyyyMMdd" of the instant in IST (synthetic reference recipe).
String istCompactDayString(DateTime date) =>
    istDayString(date).replaceAll('-', '');

class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month; // 1...12

  YearMonth(this.year, this.month) {
    if (month < 1 || month > 12) {
      throw ArgumentError('month out of range: $month');
    }
  }

  factory YearMonth.fromDate(DateTime date) {
    final c = istClock(date);
    return YearMonth(c.year, c.month);
  }

  YearMonth advancedBy(int months) {
    final total = year * 12 + (month - 1) + months;
    final y = total >= 0 ? total ~/ 12 : (total - 11) ~/ 12;
    return YearMonth(y, total - y * 12 + 1);
  }

  static List<YearMonth> monthsFromThrough(YearMonth from, YearMonth through) {
    if (from.compareTo(through) > 0) return [];
    final result = <YearMonth>[];
    var current = from;
    while (current.compareTo(through) <= 0) {
      result.add(current);
      current = current.advancedBy(1);
    }
    return result;
  }

  @override
  int compareTo(YearMonth other) =>
      (year * 12 + month) - (other.year * 12 + other.month);

  bool operator <(YearMonth other) => compareTo(other) < 0;
  bool operator <=(YearMonth other) => compareTo(other) <= 0;
  bool operator >(YearMonth other) => compareTo(other) > 0;
  bool operator >=(YearMonth other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String get displayName => '${_monthNames[month - 1]} $year';
}
