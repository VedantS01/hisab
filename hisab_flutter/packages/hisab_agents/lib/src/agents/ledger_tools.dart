/// Read-only questions over the ledger, as tools any agent may call.
///
/// Answers are short text lines in whole rupees — the on-device model reads
/// 4K tokens, tool results included. Every line is recorded with what it is
/// about, because an agent's answer may quote a number only about the thing
/// the tool said it of ([grounded]).
library;

import 'package:hisab_core/hisab_core.dart';

import '../runtime.dart';

/// One line a tool said: its [subject] (a category or merchant; empty for a
/// month's totals) and the numbers in it.
class SaidLine {
  final String subject;
  final String text;
  final Set<int> rupees;
  final Set<int> percents;

  /// The signed month-on-month change the line gives, as in "(+40%)".
  final int? change;
  SaidLine(this.subject, this.text)
      : rupees = LedgerTools.rupeesIn(text),
        percents = LedgerTools.percentsIn(text),
        change = int.tryParse(
            RegExp(r'\(([+-]\d+)%\)').firstMatch(text)?.group(1) ?? '');
}

class LedgerTools {
  final List<InsightRecord> records;
  final DateTime now;
  final InsightsConfig config;

  LedgerTools(this.records,
      {required this.now, this.config = InsightsConfig.fallback});

  /// Every line the tools have said, in order.
  final said = <SaidLine>[];

  /// Tool names in the order the model called them.
  final calls = <String>[];

  static final _monthArg = Schema.string(description: 'Month as YYYY-MM');

  late final List<AgentTool> tools = [
    _tool('monthTotals', 'Total spent and received in a month, and the number of payments.',
        {'month': _monthArg}, (a) => monthTotals(_month(a['month']))),
    _tool('spendingByCategory', "A month's spending by category, largest first, with each one's share.",
        {'month': _monthArg}, (a) => spendingByCategory(_month(a['month']))),
    _tool('topMerchants', 'Who got the most money in a month, with the number of payments.',
        {'month': _monthArg}, (a) => topMerchants(_month(a['month']))),
    _tool('compareMonths', "Each category's spending in a month against the month before it.",
        {'month': _monthArg}, (a) => compareMonths(_month(a['month']))),
    _tool('recurring', 'Payments that repeat every month or week: subscriptions, rent, EMIs.',
        {}, (_) => recurring()),
    _tool(
        'searchTransactions',
        'Payments whose merchant or category contains the words, latest first.',
        {'query': Schema.string(description: 'A merchant or category name'), 'month': _monthArg},
        (a) => searchTransactions('${a['query'] ?? ''}', _monthOrNull(a['month'])),
        optional: {'month'}),
  ];

  AgentTool _tool(String name, String description, Map<String, Map<String, Object?>> props,
          String Function(Map<String, Object?>) run,
          {Set<String> optional = const {}}) =>
      AgentTool(
        name: name,
        description: description,
        parameters: Schema.object('${name[0].toUpperCase()}${name.substring(1)}Args', props,
            optional: optional),
        run: (args) async {
          calls.add(name);
          try {
            return run(args);
          } on FormatException catch (e) {
            return e.message;
          }
        },
      );

  // MARK: - the answers

  String monthTotals(YearMonth month) {
    final rows = _in(month);
    final spent = _sum(rows.where(_isDebit));
    final received = _sum(rows.where((r) => !_isDebit(r)));
    final count = rows.where(_isDebit).length;
    return _say('', '${month.displayName}: spent ${_rupees(spent)} in $count payments; '
        'received ${_rupees(received)}.');
  }

  String spendingByCategory(YearMonth month) {
    final totals = _byKey(_in(month).where(_isDebit), (r) => r.category);
    if (totals.isEmpty) return 'No spending in ${month.displayName}.';
    final all = totals.values.fold(0, (a, b) => a + b);
    return [
      for (final e in _largest(totals, 8))
        _say(e.key, '${e.key} ${_rupees(e.value)} (${(e.value * 100 / all).round()}%)')
    ].join('\n');
  }

  String topMerchants(YearMonth month) {
    final debits = _in(month).where(_isDebit).where((r) => r.merchant.isNotEmpty);
    final totals = _byKey(debits, (r) => r.merchant);
    if (totals.isEmpty) return 'No spending in ${month.displayName}.';
    final counts = <String, int>{};
    for (final r in debits) {
      counts[r.merchant] = (counts[r.merchant] ?? 0) + 1;
    }
    return [
      for (final e in _largest(totals, 6))
        _say(e.key, '${e.key} ${_rupees(e.value)} in ${counts[e.key]} payments')
    ].join('\n');
  }

  String compareMonths(YearMonth month) {
    final before = month.advancedBy(-1);
    final now = _byKey(_in(month).where(_isDebit), (r) => r.category);
    final then = _byKey(_in(before).where(_isDebit), (r) => r.category);
    if (now.isEmpty || then.isEmpty) {
      return 'No spending to compare in ${month.displayName} and ${before.displayName}.';
    }
    final total = now.values.fold(0, (a, b) => a + b);
    final totalBefore = then.values.fold(0, (a, b) => a + b);
    final names = {...now.keys, ...then.keys}.toList()
      ..sort((a, b) => ((now[b] ?? 0) - (then[b] ?? 0))
          .abs()
          .compareTo(((now[a] ?? 0) - (then[a] ?? 0)).abs()));
    return [
      _say('', 'All spending ${_rupees(total)} in ${month.displayName}, ${_rupees(totalBefore)} '
          'in ${before.displayName}${_change(total, totalBefore)}'),
      for (final name in names.take(6))
        _say(name, '$name ${_rupees(now[name] ?? 0)}, was ${_rupees(then[name] ?? 0)}'
            '${_change(now[name] ?? 0, then[name] ?? 0)}'),
    ].join('\n');
  }

  String recurring() {
    final series = RecurrenceDetector.series(records: records, now: now, config: config)
      ..sort((a, b) => b.monthlyEquivalentPaise.compareTo(a.monthlyEquivalentPaise));
    if (series.isEmpty) return 'No repeating payments.';
    return [
      for (final s in series.take(8))
        _say(s.displayMerchant, '${s.displayMerchant} ${_rupees(s.medianPaise)} '
            '${s.cadence.name} since ${YearMonth.fromDate(s.firstSeen).displayName}')
    ].join('\n');
  }

  String searchTransactions(String query, YearMonth? month) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return 'Give a merchant or category.';
    final rows = [
      for (final r in month == null ? records : _in(month))
        if (words.every((w) =>
            r.merchant.toLowerCase().contains(w) || r.category.toLowerCase().contains(w)))
          r
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (rows.isEmpty) return 'Nothing matches "$query".';
    return [
      for (final r in rows.take(8))
        _say(r.merchant, '${istDayLabel(r.date)} · ${r.merchant} · '
            '${_isDebit(r) ? '' : '+'}${_rupees(r.amountPaise)} · ${r.category}')
    ].join('\n');
  }

  // MARK: - grounding

  static final _amount =
      RegExp(r'(?:₹|\brs\.?|\binr)\s*(\d[\d,]*(?:\.\d+)?)', caseSensitive: false);
  static final _percentage = RegExp(r'(\d+(?:\.\d+)?)\s*%');

  /// Whole rupees written in [text] ("₹1,23,456", "Rs 99").
  static Set<int> rupeesIn(String text) => {
        for (final m in _amount.allMatches(text))
          if (double.tryParse(m.group(1)!.replaceAll(',', '')) case final v?) v.round()
      };

  /// Percentages written in [text], unsigned: "40% less" for a tool's "-40%".
  static Set<int> percentsIn(String text) =>
      {for (final m in _percentage.allMatches(text)) double.parse(m.group(1)!).round()};

  /// Words that say a sentence is about the month as a whole.
  static final _wholeMonth = RegExp(
      r'\b(total|overall|in all|altogether|all spending|income|received|salary)\b',
      caseSensitive: false);

  static final _rising = RegExp(
      r'\b(rose|rise[sn]?|up|increase[sd]?|spike[sd]?|surge[sd]?|grew|grow(s|n|ing)?|jump(s|ed)?|higher)\b',
      caseSensitive: false);
  static final _falling = RegExp(
      r'\b(fell|fall(s|en|ing)?|down|drop(s|ped)?|decrease[sd]?|lower|cut|saved?|declined?)\b',
      caseSensitive: false);

  /// Whether [text] says only what the tools said:
  ///  * every number in it is one a tool said about something it names — or
  ///    about the whole month, in a sentence about the whole month or that
  ///    names nothing in particular;
  ///  * everything it names has one of its numbers ("Groceries fell" with
  ///    Food's numbers is not about groceries);
  ///  * a rise or fall it states is the way the change it quotes went.
  /// True for a text with no numbers.
  bool grounded(String text) {
    final lower = text.toLowerCase();
    bool names(SaidLine line) =>
        line.subject.isNotEmpty && lower.contains(line.subject.toLowerCase());
    final named = said.where(names).toList();
    bool about(SaidLine line) =>
        line.subject.isEmpty ? (named.isEmpty || _wholeMonth.hasMatch(text)) : names(line);
    final rupees = rupeesIn(text), percents = percentsIn(text);
    bool quotes(SaidLine l) => l.rupees.any(rupees.contains) || l.percents.any(percents.contains);

    if (!rupees.every((n) => said.any((l) => l.rupees.contains(n) && about(l)))) return false;
    if (!percents.every((n) => said.any((l) => l.percents.contains(n) && about(l)))) return false;
    for (final subject in {for (final l in named) l.subject.toLowerCase()}) {
      if (!named.any((l) => l.subject.toLowerCase() == subject && quotes(l))) return false;
    }
    final changes = [
      for (final l in said)
        if (l.change != null && about(l) && percents.contains(l.change!.abs())) l.change!
    ];
    final rising = _rising.hasMatch(text), falling = _falling.hasMatch(text);
    if (changes.isNotEmpty && rising != falling) {
      if (rising && changes.any((c) => c <= 0)) return false;
      if (falling && changes.any((c) => c >= 0)) return false;
    }
    return true;
  }

  // MARK: - helpers

  String _say(String subject, String text) {
    said.add(SaidLine(subject, text));
    return text;
  }

  /// "₹1,23,457": whole rupees, Indian grouping.
  static String _rupees(int paise) =>
      Money.formatPaise((paise / 100).round() * 100).replaceFirst(RegExp(r'\.00$'), '');

  /// " (+40%)" from [before] to [now]; nothing when there was none before.
  static String _change(int now, int before) {
    if (before == 0) return '';
    final p = ((now - before) * 100 / before).round();
    return ' (${p >= 0 ? '+' : ''}$p%)';
  }

  List<InsightRecord> _in(YearMonth month) =>
      [for (final r in records) if (YearMonth.fromDate(r.date) == month) r];

  static bool _isDebit(InsightRecord r) => r.direction == Direction.debit;

  static int _sum(Iterable<InsightRecord> rows) =>
      rows.fold(0, (total, r) => total + r.amountPaise);

  static Map<String, int> _byKey(
      Iterable<InsightRecord> rows, String Function(InsightRecord) key) {
    final totals = <String, int>{};
    for (final r in rows) {
      totals[key(r)] = (totals[key(r)] ?? 0) + r.amountPaise;
    }
    return totals;
  }

  static List<MapEntry<String, int>> _largest(Map<String, int> totals, int n) =>
      (totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).toList();

  static YearMonth _month(Object? raw) =>
      _monthOrNull(raw) ?? (throw const FormatException('Give the month as YYYY-MM.'));

  static YearMonth? _monthOrNull(Object? raw) {
    final m = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch('${raw ?? ''}'.trim());
    if (m == null) return null;
    final month = int.parse(m.group(2)!);
    return month < 1 || month > 12 ? null : YearMonth(int.parse(m.group(1)!), month);
  }
}
