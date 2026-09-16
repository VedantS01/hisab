/// Rule suggestions. Port of SuggestionEngine.swift — same gates:
/// trailing 90 days; cluster total ≥ max(₹500, 2% of window debits);
/// ≥3 txns across ≥2 months; muted merchants never return.
library;

import 'categories.dart';
import 'domain.dart';
import 'year_month.dart';

class SpendRecord {
  final String merchant;
  final int amountPaise;
  final DateTime date;
  final Direction direction;
  final String effectiveCategory;
  const SpendRecord({
    required this.merchant,
    required this.amountPaise,
    required this.date,
    required this.direction,
    required this.effectiveCategory,
  });
}

class RuleSuggestion {
  final String merchantPattern;
  final String displayMerchant;
  final int totalPaise;
  final int count;
  const RuleSuggestion({
    required this.merchantPattern,
    required this.displayMerchant,
    required this.totalPaise,
    required this.count,
  });
}

class SuggestionEngine {
  static String normalize(String merchant) {
    final cleaned = merchant
        .toLowerCase()
        .split('')
        .map((ch) => RegExp(r'[a-z]').hasMatch(ch) ? ch : ' ')
        .join();
    return cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).take(3).join(' ');
  }

  static List<RuleSuggestion> queue({
    required List<SpendRecord> records,
    required DateTime now,
    required Set<String> muted,
  }) {
    final windowStart = now.subtract(const Duration(days: 90));

    var windowDebitTotal = 0;
    final clusters = <String, List<SpendRecord>>{};
    for (final record in records) {
      if (record.direction != Direction.debit) continue;
      if (record.date.isBefore(windowStart) || record.date.isAfter(now)) {
        continue;
      }
      windowDebitTotal += record.amountPaise;
      final uncategorized =
          record.effectiveCategory == Categorizer.uncategorized ||
              record.effectiveCategory == Categorizer.miscellaneous;
      if (!uncategorized) continue;
      final key = normalize(record.merchant);
      if (key.isEmpty || muted.contains(key)) continue;
      clusters.putIfAbsent(key, () => []).add(record);
    }

    const floor = 50000; // ₹500
    final threshold = windowDebitTotal * 2 ~/ 100;
    final gate = threshold > floor ? threshold : floor;

    final suggestions = <RuleSuggestion>[];
    clusters.forEach((key, members) {
      if (members.length < 3) return;
      final months = members.map((m) => YearMonth.fromDate(m.date)).toSet();
      if (months.length < 2) return;
      var total = 0;
      final rawCounts = <String, int>{};
      for (final member in members) {
        total += member.amountPaise;
        rawCounts[member.merchant] = (rawCounts[member.merchant] ?? 0) + 1;
      }
      if (total < gate) return;
      var display = key;
      var bestCount = -1;
      rawCounts.forEach((raw, count) {
        if (count > bestCount || (count == bestCount && raw.compareTo(display) < 0)) {
          display = raw;
          bestCount = count;
        }
      });
      suggestions.add(RuleSuggestion(
          merchantPattern: key,
          displayMerchant: display,
          totalPaise: total,
          count: members.length));
    });

    suggestions.sort((l, r) => l.totalPaise == r.totalPaise
        ? l.merchantPattern.compareTo(r.merchantPattern)
        : r.totalPaise.compareTo(l.totalPaise));
    return suggestions;
  }
}
