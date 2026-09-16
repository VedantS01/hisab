/// Currency formatting. All amounts are integer paise; display uses Indian
/// digit grouping. Port of Money.swift.
library;

class Money {
  /// 1234567890 paise -> "₹1,23,45,678.90". Negatives render "-₹…";
  /// `signed` forces "+" on positives.
  static String formatPaise(int paise, {bool signed = false}) {
    final negative = paise < 0;
    final magnitude = paise.abs();
    final rupees = magnitude ~/ 100;
    final fraction = magnitude % 100;
    final grouped = _indianGrouped(rupees.toString());
    final prefix = negative ? '-' : (signed ? '+' : '');
    return '$prefix₹$grouped.${fraction.toString().padLeft(2, '0')}';
  }

  /// "-453.00" -> -45300; "+600" -> 60000; commas tolerated. Null when not a
  /// decimal amount. Port of Money.signedPaise(fromDecimalString:).
  static int? signedPaise(String raw) {
    var text = raw.trim().replaceAll(',', '');
    var sign = 1;
    if (text.startsWith('-')) {
      sign = -1;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    final parts = text.split('.');
    if (parts.length > 2 || parts[0].isEmpty) return null;
    final rupees = int.tryParse(parts[0]);
    if (rupees == null || rupees < 0) return null;
    // Reject non-digit rupee strings that int.parse would accept (none in
    // Dart's default parse besides leading +/- already stripped).
    if (!RegExp(r'^\d+$').hasMatch(parts[0])) return null;
    var fraction = 0;
    if (parts.length == 2) {
      final digits = parts[1];
      if (digits.isEmpty || digits.length > 2) return null;
      final value = int.tryParse(digits);
      if (value == null || !RegExp(r'^\d+$').hasMatch(digits)) return null;
      fraction = digits.length == 1 ? value * 10 : value;
    }
    return sign * (rupees * 100 + fraction);
  }

  /// Indian grouping: last three digits, then groups of two.
  /// "12345678" -> "1,23,45,678".
  static String _indianGrouped(String digits) {
    if (digits.length <= 3) return digits;
    final head = digits.substring(0, digits.length - 3);
    final tail = digits.substring(digits.length - 3);
    final groups = <String>[];
    var remaining = head;
    while (remaining.length > 2) {
      groups.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) groups.insert(0, remaining);
    return ([...groups, tail]).join(',');
  }
}
