/// Statement date parsing for the fixed set of patterns FormatSpecs declare.
/// Returns instants at IST midnight so IST day/month derivation matches iOS.
library;

import '../year_month.dart';

class StatementDate {
  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Supported patterns: dd/MM/yyyy, dd/MM/yy, dd-MM-yyyy, dd MMM yyyy,
  /// dd-MMM-yyyy, dd-MMM-yy, yyyy-MM-dd (the candidate set shared with iOS).
  static DateTime? tryParse(String text, String pattern) {
    final t = text.trim();
    int? day, month, year;

    List<String>? split(String sep, int count) {
      final parts = t.split(sep);
      return parts.length == count ? parts : null;
    }

    int? mon(String token) => _months[token.toLowerCase().substring(
        0, token.length >= 3 ? 3 : token.length)];

    switch (pattern) {
      case 'dd/MM/yyyy':
      case 'dd/MM/yy':
        final p = split('/', 3);
        if (p == null) return null;
        day = int.tryParse(p[0]);
        month = int.tryParse(p[1]);
        year = int.tryParse(p[2]);
        if (pattern == 'dd/MM/yy') {
          if (p[2].length != 2 || year == null) return null;
          year += 2000;
        } else if (p[2].length != 4) {
          return null;
        }
      case 'dd-MM-yyyy':
        final p = split('-', 3);
        if (p == null || p[2].length != 4) return null;
        day = int.tryParse(p[0]);
        month = int.tryParse(p[1]);
        year = int.tryParse(p[2]);
      case 'dd MMM yyyy':
        final p = t.split(RegExp(r'\s+'));
        if (p.length != 3 || p[2].length != 4) return null;
        day = int.tryParse(p[0]);
        month = mon(p[1]);
        year = int.tryParse(p[2]);
      case 'dd-MMM-yyyy':
      case 'dd-MMM-yy':
        final p = split('-', 3);
        if (p == null) return null;
        day = int.tryParse(p[0]);
        month = mon(p[1]);
        year = int.tryParse(p[2]);
        if (pattern == 'dd-MMM-yy') {
          if (p[2].length != 2 || year == null) return null;
          year += 2000;
        } else if (p[2].length != 4) {
          return null;
        }
      case 'yyyy-MM-dd':
        final p = split('-', 3);
        if (p == null || p[0].length != 4) return null;
        year = int.tryParse(p[0]);
        month = int.tryParse(p[1]);
        day = int.tryParse(p[2]);
      default:
        return null;
    }

    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    // Reject rollover (e.g. 31/02): round-trip check.
    final utc = DateTime.utc(year, month, day);
    if (utc.month != month || utc.day != day) return null;
    return utc.subtract(istOffset); // IST midnight as an instant
  }
}
