/// Analytics over counted rows. Port of Analytics.swift.
library;

import 'domain.dart';
import 'year_month.dart';

/// One "counted" row: payment-app transactions plus unmatched bank rows;
/// matched bank evidence and self transfers are excluded upstream.
class AnalyticsTxn {
  final YearMonth month;
  final int amountPaise;
  final Direction direction;
  final String category;
  final String merchant;
  final SourceKind sourceKind;
  const AnalyticsTxn({
    required this.month,
    required this.amountPaise,
    required this.direction,
    required this.category,
    required this.merchant,
    required this.sourceKind,
  });
}

/// A month's money. Debits split three ways: [spendPaise] is what was
/// consumed; [investedPaise] and [insuredPaise] (the [Analytics.investments]
/// and [Analytics.insurance] categories) left the account but were set aside,
/// not spent. [outPaise] is all three.
class MonthStats {
  final YearMonth month;
  final int spendPaise;
  final int incomePaise;
  final int investedPaise;
  final int insuredPaise;
  const MonthStats(
      {required this.month,
      required this.spendPaise,
      required this.incomePaise,
      this.investedPaise = 0,
      this.insuredPaise = 0});
  int get outPaise => spendPaise + investedPaise + insuredPaise;
  int get netPaise => incomePaise - outPaise;

  @override
  bool operator ==(Object other) =>
      other is MonthStats &&
      other.month == month &&
      other.spendPaise == spendPaise &&
      other.incomePaise == incomePaise &&
      other.investedPaise == investedPaise &&
      other.insuredPaise == insuredPaise;
  @override
  int get hashCode =>
      Object.hash(month, spendPaise, incomePaise, investedPaise, insuredPaise);
}

class CategorySlice {
  final String category;
  final int paise;
  const CategorySlice(this.category, this.paise);
}

class MerchantSlice {
  final String merchant;
  final int paise;
  const MerchantSlice(this.merchant, this.paise);
}

class Analytics {
  /// Debits in these categories are set aside, not spent.
  static const investments = 'Investments';
  static const insurance = 'Insurance';

  static MonthStats monthStats(List<AnalyticsTxn> txns, YearMonth month) {
    var spend = 0, income = 0, invested = 0, insured = 0;
    for (final txn in txns) {
      if (txn.month != month) continue;
      if (txn.direction == Direction.credit) {
        income += txn.amountPaise;
      } else if (txn.category == investments) {
        invested += txn.amountPaise;
      } else if (txn.category == insurance) {
        insured += txn.amountPaise;
      } else {
        spend += txn.amountPaise;
      }
    }
    return MonthStats(
        month: month,
        spendPaise: spend,
        incomePaise: income,
        investedPaise: invested,
        insuredPaise: insured);
  }

  static List<MonthStats> trend(List<AnalyticsTxn> txns,
      {required YearMonth endingAt, required int count}) {
    return YearMonth.monthsFromThrough(endingAt.advancedBy(-(count - 1)), endingAt)
        .map((m) => monthStats(txns, m))
        .toList();
  }

  static List<MapEntry<String, int>> _debitTotals(
      List<AnalyticsTxn> txns, YearMonth month, String Function(AnalyticsTxn) key) {
    final totals = <String, int>{};
    for (final txn in txns) {
      if (txn.month != month || txn.direction != Direction.debit) continue;
      totals[key(txn)] = (totals[key(txn)] ?? 0) + txn.amountPaise;
    }
    final entries = totals.entries.toList()
      ..sort((l, r) =>
          l.value == r.value ? l.key.compareTo(r.key) : r.value.compareTo(l.value));
    return entries;
  }

  static List<CategorySlice> categoryBreakdown(
      List<AnalyticsTxn> txns, YearMonth month, {required int top}) {
    final totals = _debitTotals(txns, month, (t) => t.category)
        .map((e) => CategorySlice(e.key, e.value))
        .toList();
    if (totals.length <= top) return totals;
    var rest = 0;
    for (final slice in totals.skip(top)) {
      rest += slice.paise;
    }
    return [...totals.take(top), CategorySlice('Other', rest)];
  }

  static List<MerchantSlice> topMerchants(
      List<AnalyticsTxn> txns, YearMonth month, {required int top}) {
    return _debitTotals(txns, month, (t) => t.merchant)
        .take(top)
        .map((e) => MerchantSlice(e.key, e.value))
        .toList();
  }
}
