import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../widgets/detection_views.dart';
import '../widgets/txn_sheets.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  /// 0 shows Transactions, 1 Detections. Shared so a notification with no
  /// memo of its own can land on Detections.
  static final segment = ValueNotifier<int>(0);

  /// A category to filter by when the screen next opens — a feed card's
  /// action. Taken as it is read.
  static final requestedCategory = ValueNotifier<String?>(null);

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum TxnSort {
  newest('Newest first'),
  oldest('Oldest first'),
  largest('Largest first'),
  smallest('Smallest first');

  final String label;
  const TxnSort(this.label);
}

/// What the list shows: a search over payee, narration, reference, category
/// and amount, and filters that AND together (values within one filter OR).
class TxnFilter {
  final String query;
  final Set<YearMonth> months;
  final Set<Source> sources;
  final Set<String> categories;
  final Direction? direction;
  final int? minPaise;
  final int? maxPaise;
  final TxnSort sort;

  const TxnFilter({
    this.query = '',
    this.months = const {},
    this.sources = const {},
    this.categories = const {},
    this.direction,
    this.minPaise,
    this.maxPaise,
    this.sort = TxnSort.newest,
  });

  bool get narrows =>
      months.isNotEmpty ||
      sources.isNotEmpty ||
      categories.isNotEmpty ||
      direction != null ||
      minPaise != null ||
      maxPaise != null;

  bool get active => narrows || query.trim().isNotEmpty;

  TxnFilter copyWith({
    String? query,
    Set<YearMonth>? months,
    Set<Source>? sources,
    Set<String>? categories,
    Direction? Function()? direction,
    int? Function()? minPaise,
    int? Function()? maxPaise,
    TxnSort? sort,
  }) => TxnFilter(
    query: query ?? this.query,
    months: months ?? this.months,
    sources: sources ?? this.sources,
    categories: categories ?? this.categories,
    direction: direction != null ? direction() : this.direction,
    minPaise: minPaise != null ? minPaise() : this.minPaise,
    maxPaise: maxPaise != null ? maxPaise() : this.maxPaise,
    sort: sort ?? this.sort,
  );

  bool matches(StoredTransaction txn, String category) {
    if (months.isNotEmpty &&
        !months.contains(YearMonth.fromDate(dateOf(txn)))) {
      return false;
    }
    if (sources.isNotEmpty && !sources.contains(sourceOf(txn))) return false;
    if (categories.isNotEmpty && !categories.contains(category)) return false;
    if (direction != null && directionOf(txn) != direction) return false;
    if (minPaise != null && txn.amountPaise < minPaise!) return false;
    if (maxPaise != null && txn.amountPaise > maxPaise!) return false;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final rupees = (txn.amountPaise / 100).toStringAsFixed(2);
    return txn.counterparty.toLowerCase().contains(q) ||
        txn.narration.toLowerCase().contains(q) ||
        (txn.reference?.toLowerCase().contains(q) ?? false) ||
        category.toLowerCase().contains(q) ||
        rupees.contains(q.replaceAll(',', '').replaceAll('₹', ''));
  }

  int compare(StoredTransaction a, StoredTransaction b) => switch (sort) {
    TxnSort.newest => b.dateMs.compareTo(a.dateMs),
    TxnSort.oldest => a.dateMs.compareTo(b.dateMs),
    TxnSort.largest => b.amountPaise.compareTo(a.amountPaise),
    TxnSort.smallest => a.amountPaise.compareTo(b.amountPaise),
  };
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  var _filter = const TxnFilter();
  final _search = TextEditingController();

  /// Row uuids picked in multi-select; non-empty means selection mode.
  final _picked = <String>{};

  /// What the list showed last build, for Select all.
  List<String> _shownUuids = const [];

  @override
  void initState() {
    super.initState();
    TransactionsScreen.segment.addListener(_onSegment);
    TransactionsScreen.requestedCategory.addListener(_takeCategory);
    _takeCategory();
  }

  void _takeCategory() {
    final category = TransactionsScreen.requestedCategory.value;
    if (category == null) return;
    TransactionsScreen.requestedCategory.value = null;
    _search.clear();
    _picked.clear();
    _filter = TxnFilter(categories: {category});
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TransactionsScreen.segment.removeListener(_onSegment);
    TransactionsScreen.requestedCategory.removeListener(_takeCategory);
    _search.dispose();
    super.dispose();
  }

  void _onSegment() => setState(_picked.clear);

  void _toggle(String uuid) => setState(
    () => _picked.contains(uuid) ? _picked.remove(uuid) : _picked.add(uuid),
  );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final segment = TransactionsScreen.segment.value;
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        final waiting = data?.detections.length ?? 0;
        final selecting = segment == 0 && _picked.isNotEmpty;
        return PopScope(
          canPop: !selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) setState(_picked.clear);
          },
          child: Scaffold(
            appBar: selecting && data != null
                ? _selectionBar(data)
                : AppBar(
                    title: const Text('Transactions'),
                    actions: [
                      if (data != null && segment == 0)
                        IconButton(
                          tooltip: 'Filter and sort',
                          icon: Icon(
                            _filter.narrows || _filter.sort != TxnSort.newest
                                ? Icons.filter_alt
                                : Icons.filter_alt_outlined,
                            color: _filter.narrows
                                ? context.hisab.brandText
                                : null,
                          ),
                          onPressed: () => _showFilters(data),
                        ),
                      if (segment == 1)
                        FutureBuilder<bool>(
                          future: canFindInText,
                          builder: (context, can) => can.data == true
                              ? IconButton(
                                  tooltip: 'Find in text',
                                  icon: const Icon(Icons.content_paste_search),
                                  onPressed: () => showFindInText(context),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
            body: data == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (!selecting)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            HisabSpace.gutter,
                            0,
                            HisabSpace.gutter,
                            HisabSpace.s8,
                          ),
                          child: SegmentedTabs(
                            segments: [
                              'Transactions',
                              waiting == 0
                                  ? 'Detections'
                                  : 'Detections · $waiting',
                            ],
                            selectedIndex: segment,
                            onChanged: (i) =>
                                TransactionsScreen.segment.value = i,
                          ),
                        ),
                      if (segment == 0) ...[_searchField(), _activeFilters()],
                      Expanded(
                        child: segment == 0
                            ? _list(data)
                            : DetectionsList(data: data),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _selectionBar(Snapshot data) {
    final all = _shownUuids.isNotEmpty && _picked.containsAll(_shownUuids);
    return AppBar(
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Icons.close),
        onPressed: () => setState(_picked.clear),
      ),
      title: Text('${_picked.length} selected'),
      actions: [
        IconButton(
          tooltip: all ? 'Select none' : 'Select all',
          icon: Icon(all ? Icons.deselect : Icons.select_all),
          onPressed: () => setState(
            () => all
                ? _picked.removeAll(_shownUuids)
                : _picked.addAll(_shownUuids),
          ),
        ),
        IconButton(
          tooltip: 'Set category',
          icon: const Icon(Icons.sell_outlined),
          onPressed: () => _categorizePicked(data),
        ),
      ],
    );
  }

  Future<void> _categorizePicked(Snapshot data) async {
    final state = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final option = await pickCategory(
      context,
      categoryOptions(Queries.rules(data.ruleRows)),
      title: 'Category for ${_picked.length}',
    );
    if (option == null) return;
    final count = _picked.length;
    await setCategory(state.db, _picked, option);
    if (!mounted) return;
    setState(_picked.clear);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$count ${count == 1 ? 'transaction' : 'transactions'} '
          'set to $option',
        ),
      ),
    );
  }

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(
      HisabSpace.gutter,
      0,
      HisabSpace.gutter,
      HisabSpace.s8,
    ),
    child: TextField(
      controller: _search,
      onChanged: (q) => setState(() => _filter = _filter.copyWith(query: q)),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search payee, note, ref or amount',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _search.clear();
                  _filter = _filter.copyWith(query: '');
                }),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HisabRadius.pill),
        ),
      ),
    ),
  );

  /// The filters in force as chips; tapping one takes it off.
  Widget _activeFilters() {
    final f = _filter;
    final chips = <(String, TxnFilter)>[
      for (final m in f.months)
        (m.displayName, f.copyWith(months: {...f.months}..remove(m))),
      for (final s in f.sources)
        (s.displayName, f.copyWith(sources: {...f.sources}..remove(s))),
      for (final c in f.categories)
        (c, f.copyWith(categories: {...f.categories}..remove(c))),
      if (f.direction != null)
        (
          f.direction == Direction.credit ? 'Money in' : 'Money out',
          f.copyWith(direction: () => null),
        ),
      if (f.minPaise != null)
        (
          '≥ ${AmountText.format(f.minPaise!)}',
          f.copyWith(minPaise: () => null),
        ),
      if (f.maxPaise != null)
        (
          '≤ ${AmountText.format(f.maxPaise!)}',
          f.copyWith(maxPaise: () => null),
        ),
      if (f.sort != TxnSort.newest)
        (f.sort.label, f.copyWith(sort: TxnSort.newest)),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: HisabSpace.gutter),
        children: [
          for (final (label, without) in chips)
            Padding(
              padding: const EdgeInsets.only(right: HisabSpace.s8),
              child: InputChip(
                label: Text(label),
                onDeleted: () => setState(() => _filter = without),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(Snapshot data) {
    final ruleList = Queries.rules(data.ruleRows);
    final matcher = CategoryMatcher(ruleList);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    final rows =
        [
            for (final txn in Queries.visible(data.txns, data.matches))
              (txn, Queries.effectiveCategory(txn, matcher, selfTransfers)),
          ].where((r) => _filter.matches(r.$1, r.$2)).toList()
          ..sort((a, b) => _filter.compare(a.$1, b.$1));
    _shownUuids = [for (final r in rows) r.$1.uuid];
    // Rows that left the list (filtered out, or gone) leave the selection.
    _picked.retainAll(_shownUuids);

    if (rows.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: _filter.active ? 'Nothing matches' : 'No transactions yet',
        message: _filter.active
            ? 'Try a shorter search or fewer filters.'
            : 'Import a statement from the Dashboard.',
        actionLabel: _filter.active ? 'Clear search and filters' : null,
        onAction: _filter.active
            ? () => setState(() {
                _search.clear();
                _filter = const TxnFilter();
              })
            : null,
      );
    }

    final selecting = _picked.isNotEmpty;
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final (txn, category) = rows[index];
        return TxnRow(
          leading: MerchantAvatar(
            name: txn.counterparty.isEmpty ? '?' : txn.counterparty,
          ),
          title: txn.counterparty,
          subtitle: '${istDayLabel(dateOf(txn))} · $category',
          paise: txn.amountPaise,
          tone: directionOf(txn) == Direction.credit
              ? AmountTone.credit
              : AmountTone.debit,
          selected: _picked.contains(txn.uuid),
          onTap: selecting
              ? () => _toggle(txn.uuid)
              : () => showTxnDetail(context, txn, category, ruleList),
          onLongPress: () => _toggle(txn.uuid),
        );
      },
    );
  }

  void _showFilters(Snapshot data) {
    final matcher = Queries.matcher(data.ruleRows);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    final months = {
      for (final txn in data.txns) YearMonth.fromDate(dateOf(txn)),
    }.toList()..sort((a, b) => b.compareTo(a));
    final sources = Source.ordered(data.txns.map(sourceOf));
    final categories = {
      for (final txn in Queries.visible(data.txns, data.matches))
        Queries.effectiveCategory(txn, matcher, selfTransfers),
    }.toList()..sort();
    String rupees(int? paise) =>
        paise == null ? '' : (paise / 100).toStringAsFixed(0);
    int? paiseOf(String text) {
      final value = double.tryParse(text.replaceAll(',', '').trim());
      return value == null ? null : (value * 100).round();
    }

    final min = TextEditingController(text: rupees(_filter.minPaise));
    final max = TextEditingController(text: rupees(_filter.maxPaise));

    showHisabSheet<void>(
      context: context,
      title: 'Filter and sort',
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(TxnFilter next) {
            setSheet(() {});
            setState(() => _filter = next);
          }

          Set<T> flip<T>(Set<T> set, T value) =>
              set.contains(value) ? ({...set}..remove(value)) : {...set, value};

          return ListView(
            shrinkWrap: true,
            children: [
              _section<TxnSort>(
                'Sort',
                TxnSort.values,
                (s) => s.label,
                (s) => _filter.sort == s,
                (s) => update(_filter.copyWith(sort: s)),
              ),
              _section<Direction>(
                'Direction',
                const [Direction.debit, Direction.credit],
                (d) => d == Direction.credit ? 'Money in' : 'Money out',
                (d) => _filter.direction == d,
                (d) => update(
                  _filter.copyWith(
                    direction: () => _filter.direction == d ? null : d,
                  ),
                ),
              ),
              _section<YearMonth>(
                'Month',
                months,
                (m) => m.displayName,
                (m) => _filter.months.contains(m),
                (m) =>
                    update(_filter.copyWith(months: flip(_filter.months, m))),
              ),
              _section<Source>(
                'Source',
                sources,
                (s) => s.displayName,
                (s) => _filter.sources.contains(s),
                (s) =>
                    update(_filter.copyWith(sources: flip(_filter.sources, s))),
              ),
              _section<String>(
                'Category',
                categories,
                (c) => c,
                (c) => _filter.categories.contains(c),
                (c) => update(
                  _filter.copyWith(categories: flip(_filter.categories, c)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Amount (₹)', style: HisabType.caption),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: min,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'From',
                      ),
                      onChanged: (t) =>
                          update(_filter.copyWith(minPaise: () => paiseOf(t))),
                    ),
                  ),
                  const SizedBox(width: HisabSpace.s12),
                  Expanded(
                    child: TextField(
                      controller: max,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'To',
                      ),
                      onChanged: (t) =>
                          update(_filter.copyWith(maxPaise: () => paiseOf(t))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HisabSpace.s12),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      min.clear();
                      max.clear();
                      update(TxnFilter(query: _filter.query));
                    },
                    child: Text(
                      'Clear all',
                      style: TextStyle(color: context.hisab.brandText),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      min.dispose();
      max.dispose();
    });
  }

  Widget _section<T>(
    String label,
    List<T> options,
    String Function(T) name,
    bool Function(T) isOn,
    void Function(T) onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: HisabType.caption),
          const SizedBox(height: HisabSpace.s4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(name(option)),
                  selected: isOn(option),
                  onSelected: (_) => onTap(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
