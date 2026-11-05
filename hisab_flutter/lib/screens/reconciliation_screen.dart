import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/detections.dart';
import '../services/memo_store.dart';
import '../services/queries.dart';
import '../state.dart';
import '../storage/database.dart';
import '../widgets/detection_edit_sheet.dart';

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
    final detections = data.detections;
    if (months.isEmpty && detections.isEmpty) {
      return const EmptyState(
        icon: Icons.compare_arrows_rounded,
        title: 'Nothing to reconcile',
        message: 'Import an app and a bank statement for the same month.',
      );
    }
    if (months.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(HisabSpace.gutter),
        children: _detectionSection(data, detections),
      );
    }
    if (!months.contains(_month)) _month = months.first;

    final (app, bank) = Queries.reconProjection(data.txns, _month);
    final result = Reconciler.reconcile(app: app, bank: bank);
    final byUuid = {for (final txn in data.txns) txn.uuid: txn};
    final selfTransfers = Queries.selfTransferUuids(data.txns);

    final c = context.hisab;
    Widget section(String title, HisabTone tone, List<String> ids,
        {String empty = 'None'}) {
      final colors = c.tone(tone);
      return Padding(
        padding: const EdgeInsets.only(bottom: HisabSpace.s12),
        child: SurfaceCard(
          padding: EdgeInsets.zero,
          child: Container(
            decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.fg, width: 4))),
            padding: const EdgeInsets.fromLTRB(
                HisabSpace.s12, HisabSpace.s16, HisabSpace.s16, HisabSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(title, style: HisabType.title)),
                  StatusTag('${ids.length}', tone: tone),
                ]),
                if (ids.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: HisabSpace.s4),
                    child: Text(empty,
                        style:
                            HisabType.caption.copyWith(color: c.textSecondary)),
                  ),
                if (ids.isNotEmpty) const SizedBox(height: HisabSpace.s8),
                for (final id in ids.take(30))
                  if (byUuid[id] case final txn?)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              txn.counterparty,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: HisabType.label,
                            ),
                          ),
                          if (selfTransfers.contains(id)) ...[
                            const StatusTag('Self transfer'),
                            const SizedBox(width: HisabSpace.s8),
                          ],
                          AmountText(txn.amountPaise, role: AmountRole.sm),
                        ],
                      ),
                    ),
                if (ids.length > 30)
                  Text('…and ${ids.length - 30} more',
                      style:
                          HisabType.caption.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._detectionSection(data, detections),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final month in months)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: HisabFilterChip(
                    label: month.displayName,
                    selected: month == _month,
                    onSelected: (_) => setState(() => _month = month),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: HisabSpace.s12),
        Row(
          children: [
            Expanded(
                child:
                    _stat('Matched', result.matches.length, HisabTone.credit)),
            const SizedBox(width: HisabSpace.s8),
            Expanded(
                child: _stat(
                    'App only', result.appUnmatched.length, HisabTone.brand)),
            const SizedBox(width: HisabSpace.s8),
            Expanded(
                child: _stat(
                    'Bank only', result.bankOnly.length, HisabTone.spend)),
          ],
        ),
        const SizedBox(height: HisabSpace.s12),
        section('Bank confirms', HisabTone.credit,
            [for (final m in result.matches) m.appID],
            empty: 'No app payment matched a bank row yet.'),
        section(
            'App only, awaiting the bank', HisabTone.brand, result.appUnmatched,
            empty: 'Every app payment is bank-confirmed.'),
        section('Bank only', HisabTone.spend, result.bankOnly,
            empty: 'No bank-only spending this month.'),
      ],
    );
  }

  /// Open detections first: each one editable, with the row it most likely
  /// is offered right there. Empty when there are none.
  List<Widget> _detectionSection(
      Snapshot data, List<StoredPendingMemo> detections) {
    if (detections.isEmpty) return const [];
    final c = context.hisab;
    return [
      SectionHeader(title: 'Detections'),
      Text(
        'Payments Hisab saw that are not in the ledger yet. Tap one to '
        'correct it or add a reference; link it when the bank row is here.',
        style: HisabType.caption.copyWith(color: c.textSecondary),
      ),
      const SizedBox(height: HisabSpace.s8),
      for (final memo in detections.take(20)) _detectionCard(data, memo),
      const SizedBox(height: HisabSpace.s12),
    ];
  }

  Widget _detectionCard(Snapshot data, StoredPendingMemo memo) {
    final suggestions = Detections.suggestions(memo, data);
    final best = suggestions.firstOrNull;
    final db = AppScope.of(context).db;
    return Padding(
      padding: const EdgeInsets.only(bottom: HisabSpace.s8),
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            TxnRow(
              leading: MerchantAvatar(name: memo.payee.isEmpty ? '?' : memo.payee),
              title: memo.payee.isEmpty ? 'Unnamed' : memo.payee,
              subtitle: [
                istDayLabel(
                    DateTime.fromMillisecondsSinceEpoch(memo.dateMs, isUtc: true)),
                if (memo.accountTail != null) '••${memo.accountTail}',
                if (best == null) 'no match yet',
              ].join(' · '),
              paise: memo.amountPaise,
              tone: memo.directionValue == Direction.credit
                  ? AmountTone.credit
                  : AmountTone.debit,
              status: memo.assignedCategory == null
                  ? null
                  : StatusTag(memo.assignedCategory!, tone: HisabTone.brand),
              onTap: () => showDetectionEditSheet(context, memo.captureHash),
            ),
            if (best != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    HisabSpace.s16, 0, HisabSpace.s8, HisabSpace.s8),
                child: SuggestionRow(
                  txn: best.$1,
                  verdict: best.$2,
                  busy: false,
                  onLink: () =>
                      Detections.link(memo.captureHash, best.$1.uuid, db: db),
                  onReject: () =>
                      Detections.reject(memo.captureHash, best.$1.uuid, db: db),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int count, HisabTone tone) => BentoTile(
        value: Text('$count',
            style: TextStyle(color: context.hisab.tone(tone).fg)),
        label: label,
      );
}
