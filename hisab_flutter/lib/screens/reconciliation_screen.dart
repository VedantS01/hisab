import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/queries.dart';
import '../state.dart';
import '../theme.dart';

class ReconciliationScreen extends StatefulWidget {
  const ReconciliationScreen({super.key});

  @override
  State<ReconciliationScreen> createState() => _ReconciliationScreenState();
}

class _ReconciliationScreenState extends State<ReconciliationScreen> {
  YearMonth _month = YearMonth.fromDate(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(title: const Text('Reconciliation')),
          body: data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(data),
        );
      },
    );
  }

  Widget _body(Snapshot data) {
    final months = {
      for (final txn in data.txns) YearMonth.fromDate(dateOf(txn))
    }.toList()
      ..sort((a, b) => b.compareTo(a));
    if (months.isEmpty) {
      return const Center(
        child: Text('Import app and bank statements to reconcile.',
            style: TextStyle(color: Colors.black54)),
      );
    }
    if (!months.contains(_month)) _month = months.first;

    final (app, bank) = Queries.reconProjection(data.txns, _month);
    final result = Reconciler.reconcile(app: app, bank: bank);
    final byUuid = {for (final txn in data.txns) txn.uuid: txn};
    final selfTransfers = Queries.selfTransferUuids(data.txns);

    Widget section(String title, Color color, List<String> ids,
        {String empty = 'None'}) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$title (${ids.length})',
                  style:
                      TextStyle(fontWeight: FontWeight.w600, color: color)),
              if (ids.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(empty,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
                ),
              for (final id in ids.take(30))
                if (byUuid[id] case final txn?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${txn.counterparty}'
                            '${selfTransfers.contains(id) ? '  ·  Self Transfer' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(Money.formatPaise(txn.amountPaise),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              if (ids.length > 30)
                Text('…and ${ids.length - 30} more',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final month in months)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(month.displayName),
                    selected: month == _month,
                    onSelected: (_) => setState(() => _month = month),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _stat('Matched', result.matches.length, HisabTheme.hara),
                _stat('App only', result.appUnmatched.length, HisabTheme.sona),
                _stat('Bank only', result.bankOnly.length, HisabTheme.khataRed),
              ],
            ),
          ),
        ),
        section('Bank confirms', HisabTheme.hara,
            [for (final m in result.matches) m.appID],
            empty: 'No app payment matched a bank row yet.'),
        section('App only — awaiting bank statement', HisabTheme.sona,
            result.appUnmatched,
            empty: 'Every app payment is bank-confirmed.'),
        section('Bank only — Miscellaneous / transfers', HisabTheme.khataRed,
            result.bankOnly,
            empty: 'No bank-only spending this month.'),
      ],
    );
  }

  Widget _stat(String label, int count, Color color) => Column(
        children: [
          Text('$count',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}
