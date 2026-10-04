/// Span text -> field value. Strict on purpose: a span that does not
/// normalize is absent, never repaired. Port of ml/src/hisab_ml/normalize.py.
///
/// Case mapping and whitespace are ASCII-only, exactly as the reference
/// defines them: Dart's `toLowerCase`, `trim` and `\s` all disagree with
/// Python's and Swift's on some non-ASCII input, so none of them is used.
library;

class ExtractorNormalize {
  ExtractorNormalize._();

  static const _ws = ' \t\n\r\x0b\x0c';
  static final _wsRun = RegExp('[$_ws]+');

  static String lower(String s) => String.fromCharCodes(
      s.codeUnits.map((c) => c >= 0x41 && c <= 0x5A ? c + 0x20 : c));

  static String upper(String s) => String.fromCharCodes(
      s.codeUnits.map((c) => c >= 0x61 && c <= 0x7A ? c - 0x20 : c));

  static String trim(String s) => _strip(s, _ws);

  /// Python's `str.strip(chars)`.
  static String _strip(String s, String chars) {
    var a = 0, b = s.length;
    while (a < b && chars.contains(s[a])) {
      a++;
    }
    while (b > a && chars.contains(s[b - 1])) {
      b--;
    }
    return s.substring(a, b);
  }

  // Plain digits, Indian grouping (1,23,456) or Western grouping (123,456);
  // a grouped number always ends in a 3-digit group. `(?=\n?$)` is Python's
  // `$`, which also matches before a final newline.
  static final _amount = RegExp(
      r'^(?:\d+|\d{1,2}(?:,\d{2})*,\d{3}|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?(?=\n?$)');
  static final _tail = RegExp(r'(\d{3,})$');
  static final _refPatterns = [
    RegExp(r'^\d{12}$'), // UPI RRN / IMPS ref
    RegExp(r'^[A-Z]{4}(?:[A-Z0-9]{12}|[A-Z0-9]{18})$'), // NEFT/RTGS UTR
    RegExp(r'^[A-Z](?:\d{15}|\d{21})$'), // older NEFT UTR, no bank code
  ];

  static int _digits(String s) =>
      s.codeUnits.where((c) => c >= 0x30 && c <= 0x39).length;

  static int? amountPaise(String text) {
    var s = trim(text);
    if (s.endsWith('/-')) s = s.substring(0, s.length - 2);
    if (!_amount.hasMatch(s)) return null;
    final plain = s.replaceAll(',', '');
    final dot = plain.indexOf('.');
    final rupeesText = dot < 0 ? plain : plain.substring(0, dot);
    final frac = dot < 0 ? '' : plain.substring(dot + 1);
    // Python's int() ignores the one final "\n" that `$` lets through; the
    // fraction's two-character slice is taken before it is dropped, as there.
    // A rupee figure past 64 bits is no amount the app can book.
    final rupees = int.tryParse(rupeesText.replaceAll('\n', ''));
    if (rupees == null || rupees > 92233720368547757) return null;
    return rupees * 100 +
        int.parse('${frac}00'.substring(0, 2).replaceAll('\n', ''));
  }

  /// Last 4 digits at most: XX8816, XXXXXXX8816 and XXXXX308816 are one account.
  static String? acctTail(String text) {
    final m = _tail.firstMatch(trim(text));
    if (m == null) return null;
    final run = m[1]!;
    return run.length > 4 ? run.substring(run.length - 4) : run;
  }

  static String? ref(String text) {
    final s = upper(trim(text));
    // At least 8 digits: a reference is mostly number, never a word.
    return _digits(s) >= 8 && _refPatterns.any((p) => p.hasMatch(s)) ? s : null;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static const _fullMonths = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, //
    'june': 6, 'july': 7, 'august': 8, 'september': 9, 'october': 10,
    'november': 11, 'december': 12,
  };

  // Tried in order, each a full match. Fields: d day, m month number, b month
  // abbreviation, B full month name, y year (2 or 4 digits).
  static final _datePatterns = _compile([
    (r'(\d{1,2})([-/.])(\d{1,2})\2(\d{2}|\d{4})', 'd_m_y'), // 22-09-26
    (r'(\d{1,2})-([a-z]{3})-(\d{2}|\d{4})', 'dby'), // 22-Sep-26
    (r'(\d{1,2})([a-z]{3})(\d{2}|\d{4})', 'dby'), // 22Sep26
    (r'(\d{1,2}) ([a-z]{3}) (\d{2}|\d{4})', 'dby'), // 22 Sep 2026
    (r'(\d{1,2})([- ])([a-z]+)\2(\d{4})', 'd_By'), // 22-September-2026
    (r'([a-z]{3}) (\d{1,2}), (\d{4})', 'bdy'), // Sep 22, 2026
    (r'(\d{4})-(\d{1,2})-(\d{1,2})', 'ymd'), // 2026-09-22
  ]);
  // No year: HDFC writes "14-08"; the app takes the year from the alert.
  static final _yearlessPatterns = _compile([
    (r'(\d{1,2})-(\d{1,2})', 'dm'),
    (r'(\d{1,2})/(\d{1,2})', 'dm'),
    (r'(\d{1,2})-([a-z]{3})', 'db'),
    (r'(\d{1,2}) ([a-z]{3})', 'db'),
    (r'([a-z]{3}) (\d{1,2})', 'bd'),
    (r'(\d{1,2})([a-z]{3})', 'db'),
  ]);
  static final _ordinal =
      RegExp(r'(\d)(?:st|nd|rd|th)\b', caseSensitive: false);

  static List<(RegExp, String)> _compile(List<(String, String)> patterns) => [
        for (final (p, kind) in patterns)
          (RegExp('^(?:$p)\$', caseSensitive: false), kind)
      ];

  /// strptime's %y pivot: 69-99 -> 19xx, 00-68 -> 20xx.
  static int _year(String y) {
    final n = int.parse(y);
    return y.length == 4 ? n : (n >= 69 ? 1900 + n : 2000 + n);
  }

  /// (year, month, day) from a match, or null if a month name is unknown.
  /// Yearless kinds use 2000, a leap year, so 29 Feb survives the check.
  static (int, int, int)? _ymd(String kind, List<String> g) {
    (int, int, int)? named(int? m, int y, String d) =>
        m == null ? null : (y, m, int.parse(d));
    switch (kind) {
      case 'd_m_y':
        return (_year(g[3]), int.parse(g[2]), int.parse(g[0]));
      case 'dby':
        return named(_months[lower(g[1])], _year(g[2]), g[0]);
      case 'd_By':
        return named(_fullMonths[lower(g[2])], int.parse(g[3]), g[0]);
      case 'bdy':
        return named(_months[lower(g[0])], int.parse(g[2]), g[1]);
      case 'ymd':
        return (int.parse(g[0]), int.parse(g[1]), int.parse(g[2]));
      case 'dm':
        return (2000, int.parse(g[1]), int.parse(g[0]));
      case 'db':
        return named(_months[lower(g[1])], 2000, g[0]);
      case 'bd':
        return named(_months[lower(g[0])], 2000, g[1]);
    }
    throw ArgumentError(kind);
  }

  static bool _valid(int y, int m, int d) {
    if (!(m >= 1 && m <= 12 && d >= 1)) return false;
    final leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    const days = [31, 0, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    return d <= (m == 2 ? (leap ? 29 : 28) : days[m - 1]);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// ISO date, or `--MM-DD` when the alert names no year.
  static String? dateIso(String text) {
    var s = trim(text).replaceAllMapped(_ordinal, (m) => m[1]!); // 31st -> 31
    s = trim(s.replaceAll("'", ' ').replaceAll(_wsRun, ' ')); // Oct' 2024
    for (final (patterns, yearless) in [
      (_datePatterns, false),
      (_yearlessPatterns, true),
    ]) {
      for (final (rx, kind) in patterns) {
        final m = rx.firstMatch(s);
        final ymd = m == null
            ? null
            : _ymd(kind, [for (var i = 1; i <= m.groupCount; i++) m[i]!]);
        if (ymd != null && _valid(ymd.$1, ymd.$2, ymd.$3)) {
          final (y, mo, d) = ymd;
          return yearless
              ? '--${_two(mo)}-${_two(d)}'
              : '${y.toString().padLeft(4, '0')}-${_two(mo)}-${_two(d)}';
        }
      }
    }
    return null;
  }

  static final _honorific = RegExp(r'^(?:mr|mrs|ms|miss|dr|shri|smt|m/s)\.? +');

  static String? name(String text) {
    final s = lower(_strip(text.replaceAll(_wsRun, ' '), ' .,:;-'));
    final out = s.replaceFirst(_honorific, '');
    return out.isEmpty ? null : out;
  }
}
