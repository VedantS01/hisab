import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import '../theme.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

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
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Transactions'),
            actions: [
              if (data != null)
                IconButton(
                  icon: Icon(
                      _hasFilters
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      color:
                          _hasFilters ? HisabTheme.khataRed : null),
                  onPressed: () => _showFilters(data),
                ),
            ],
          ),
          body: data == null
              ? const Center(child: CircularProgressIndicator())
              : _list(data),
        );
      },
    );
  }

  Widget _list(Snapshot data) {
    final ruleList = Queries.rules(data.ruleRows);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    var txns = Queries.visible(data.txns, data.matches);
    txns.sort((a, b) => b.dateMs.compareTo(a.dateMs));

    txns = [
      for (final txn in txns)
        if ((_monthFilter == null ||
                YearMonth.fromDate(dateOf(txn)) == _monthFilter) &&
            (_sourceFilter == null || sourceOf(txn) == _sourceFilter) &&
            (_categoryFilter == null ||
                Queries.effectiveCategory(txn, ruleList, selfTransfers) ==
                    _categoryFilter))
          txn
    ];

    if (txns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _hasFilters
                    ? 'No transactions match the active filters.'
                    : 'No transactions yet — import a statement from the Dashboard.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              if (_hasFilters)
                TextButton(
                  onPressed: () => setState(() {
                    _monthFilter = null;
                    _sourceFilter = null;
                    _categoryFilter = null;
                  }),
                  child: const Text('Clear filters',
                      style: TextStyle(color: HisabTheme.khataRed)),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: txns.length,
      itemBuilder: (context, index) {
        final txn = txns[index];
        final category =
            Queries.effectiveCategory(txn, ruleList, selfTransfers);
        return ListTile(
          leading: Icon(HisabTheme.sourceGlyph(sourceOf(txn)),
              color: HisabTheme.khataRed),
          title: Text(txn.counterparty,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${istDayString(dateOf(txn))} · $category',
              style: const TextStyle(fontSize: 12)),
          trailing: Text(
            Money.formatPaise(
                directionOf(txn) == Direction.debit
                    ? -txn.amountPaise
                    : txn.amountPaise,
                signed: true),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: HisabTheme.amountColor(directionOf(txn))),
          ),
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
    final ruleList = Queries.rules(data.ruleRows);
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    final months = {
      for (final txn in data.txns) YearMonth.fromDate(dateOf(txn))
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    final sources = Source.ordered(data.txns.map(sourceOf));
    final categories = {
      for (final txn in Queries.visible(data.txns, data.matches))
        Queries.effectiveCategory(txn, ruleList, selfTransfers)
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
