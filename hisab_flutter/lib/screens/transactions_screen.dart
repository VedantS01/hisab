import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/detection_views.dart';

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

class _TransactionsScreenState extends State<TransactionsScreen> {
  YearMonth? _monthFilter;
  Source? _sourceFilter;
  String? _categoryFilter;

  bool get _hasFilters =>
      _monthFilter != null || _sourceFilter != null || _categoryFilter != null;

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
    _monthFilter = null;
    _sourceFilter = null;
    _categoryFilter = category;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    TransactionsScreen.segment.removeListener(_onSegment);
    TransactionsScreen.requestedCategory.removeListener(_takeCategory);
    super.dispose();
  }

  void _onSegment() => setState(() {});

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
        return Scaffold(
          appBar: AppBar(
            title: const Text('Transactions'),
            actions: [
              if (data != null && segment == 0)
                IconButton(
                  icon: Icon(
                      _hasFilters
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      color:
                          _hasFilters ? HisabTheme.khataRed : null),
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(HisabSpace.gutter, 0,
                          HisabSpace.gutter, HisabSpace.s8),
                      child: SegmentedTabs(
                        segments: [
                          'Transactions',
                          waiting == 0 ? 'Detections' : 'Detections · $waiting',
                        ],
                        selectedIndex: segment,
                        onChanged: (i) => TransactionsScreen.segment.value = i,
                      ),
                    ),
                    Expanded(
                      child: segment == 0
                          ? _list(data)
                          : DetectionsList(data: data),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _list(Snapshot data) {
    final ruleList = Queries.rules(data.ruleRows);
    final matcher = CategoryMatcher(ruleList);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    var txns = Queries.visible(data.txns, data.matches);
    txns.sort((a, b) => b.dateMs.compareTo(a.dateMs));

    txns = [
      for (final txn in txns)
        if ((_monthFilter == null ||
                YearMonth.fromDate(dateOf(txn)) == _monthFilter) &&
            (_sourceFilter == null || sourceOf(txn) == _sourceFilter) &&
            (_categoryFilter == null ||
                Queries.effectiveCategory(txn, matcher, selfTransfers) ==
                    _categoryFilter))
          txn
    ];

    if (txns.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: _hasFilters ? 'Nothing matches' : 'No transactions yet',
        message: _hasFilters
            ? 'Try fewer filters.'
            : 'Import a statement from the Dashboard.',
        actionLabel: _hasFilters ? 'Clear filters' : null,
        onAction: _hasFilters
            ? () => setState(() {
                  _monthFilter = null;
                  _sourceFilter = null;
                  _categoryFilter = null;
                })
            : null,
      );
    }

    return ListView.builder(
      itemCount: txns.length,
      itemBuilder: (context, index) {
        final txn = txns[index];
        final category =
            Queries.effectiveCategory(txn, matcher, selfTransfers);
        return TxnRow(
          leading: MerchantAvatar(
              name: txn.counterparty.isEmpty ? '?' : txn.counterparty),
          title: txn.counterparty,
          subtitle: '${istDayLabel(dateOf(txn))} · $category',
          paise: txn.amountPaise,
          tone: directionOf(txn) == Direction.credit
              ? AmountTone.credit
              : AmountTone.debit,
          onTap: () => _showDetail(txn, category, ruleList),
        );
      },
    );
  }

  void _showDetail(
      StoredTransaction txn, String category, List<CategoryRule> ruleList) {
    final state = AppScope.of(context);
    final categories = {
      for (final rule in ruleList) rule.category,
      Categorizer.uncategorized,
    }.toList()
      ..sort();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(txn.counterparty,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  '${sourceOf(txn).displayName} · ${istDayString(dateOf(txn))}'),
              if (txn.reference != null)
                Text('Ref: ${txn.reference}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 8),
              Text(txn.narration,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const Divider(height: 24),
              const Text('Category',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 8,
                children: [
                  for (final option in categories)
                    ChoiceChip(
                      label: Text(option),
                      selected: option == category,
                      onSelected: (_) async {
                        await (state.db.update(state.db.storedTransactions)
                              ..where((t) => t.uuid.equals(txn.uuid)))
                            .write(StoredTransactionsCompanion(
                                categoryOverride: Value(
                                    option == Categorizer.uncategorized
                                        ? null
                                        : option)));
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilters(Snapshot data) {
    final matcher = Queries.matcher(data.ruleRows);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    final months = {
      for (final txn in data.txns) YearMonth.fromDate(dateOf(txn))
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final sources = Source.ordered(data.txns.map(sourceOf));
    final categories = {
      for (final txn in Queries.visible(data.txns, data.matches))
        Queries.effectiveCategory(txn, matcher, selfTransfers)
    }.toList()
      ..sort();

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Filters',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            _filterWrap<YearMonth>('Month', months, _monthFilter,
                (m) => m.displayName, (m) => setState(() => _monthFilter = m)),
            _filterWrap<Source>('Source', sources, _sourceFilter,
                (s) => s.displayName, (s) => setState(() => _sourceFilter = s)),
            _filterWrap<String>('Category', categories, _categoryFilter,
                (c) => c, (c) => setState(() => _categoryFilter = c)),
            TextButton(
              onPressed: () {
                setState(() {
                  _monthFilter = null;
                  _sourceFilter = null;
                  _categoryFilter = null;
                });
                Navigator.pop(sheetContext);
              },
              child: const Text('Clear all',
                  style: TextStyle(color: HisabTheme.khataRed)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterWrap<T>(String label, List<T> options, T? selected,
      String Function(T) name, void Function(T?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Wrap(
            spacing: 6,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(name(option)),
                  selected: option == selected,
                  onSelected: (on) => onChanged(on ? option : null),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
