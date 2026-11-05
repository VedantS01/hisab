/// One detection, open for correction: amount, date, who, account tail and
/// a reference. Every save matches it again against the ledger; the rows
/// it might be are listed underneath to link or turn down.
library;

import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/detections.dart';
import '../services/memo_store.dart';
import '../services/queries.dart';
import '../state.dart';
import '../storage/database.dart';

Future<void> showDetectionEditSheet(BuildContext context, String captureHash) {
  final state = AppScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        final memo = data?.memos
            .where((m) => m.captureHash == captureHash)
            .firstOrNull;
        if (data == null || memo == null) return const SizedBox(height: 120);
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: DetectionEditor(memo: memo, data: data),
        );
      },
    ),
  );
}

class DetectionEditor extends StatefulWidget {
  final StoredPendingMemo memo;
  final Snapshot data;
  const DetectionEditor({super.key, required this.memo, required this.data});

  @override
  State<DetectionEditor> createState() => _DetectionEditorState();
}

class _DetectionEditorState extends State<DetectionEditor> {
  late final _amount = TextEditingController(
      text: (widget.memo.amountPaise / 100).toStringAsFixed(2));
  late final _payee = TextEditingController(text: widget.memo.payee);
  late final _tail = TextEditingController(text: widget.memo.accountTail ?? '');
  final _reference = TextEditingController();
  late DateTime _date =
      DateTime.fromMillisecondsSinceEpoch(widget.memo.dateMs, isUtc: true);
  bool _busy = false;

  static final _referenceShape = RegExp(r'^[A-Za-z0-9]{6,}$');

  @override
  void dispose() {
    for (final c in [_amount, _payee, _tail, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _paise {
    final value = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return value == null || value <= 0 ? null : (value * 100).round();
  }

  bool get _dirty =>
      _paise != widget.memo.amountPaise ||
      _payee.text.trim() != widget.memo.payee ||
      _tail.text.trim() != (widget.memo.accountTail ?? '') ||
      _date.millisecondsSinceEpoch != widget.memo.dateMs;

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final memo = widget.memo;
    final credit = memo.directionValue == Direction.credit;
    final suggestions = Detections.suggestions(memo, widget.data);
    final reference = _reference.text.trim();
    final canSave = _paise != null &&
        !_busy &&
        (reference.isEmpty ? _dirty : _referenceShape.hasMatch(reference));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(HisabSpace.s20, 0, HisabSpace.s20, HisabSpace.s24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(credit ? 'Money in' : 'Money out', style: HisabType.titleLg)),
              StatusTag(istDayLabel(_date)),
            ]),
            const SizedBox(height: HisabSpace.s4),
            Text(
              'Seen ${istDayLabel(DateTime.fromMillisecondsSinceEpoch(memo.capturedAtMs, isUtc: true))}. '
              'What you write here is kept; later sightings only fill the blanks.',
              style: HisabType.caption.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: HisabSpace.s16),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('detection-amount'),
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: HisabSpace.s12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(istDayLabel(_date)),
                ),
              ),
            ]),
            TextField(
              key: const Key('detection-payee'),
              controller: _payee,
              decoration: InputDecoration(labelText: credit ? 'From' : 'Paid to'),
              onChanged: (_) => setState(() {}),
            ),
            Row(children: [
              Expanded(
                child: TextField(
                  key: const Key('detection-tail'),
                  controller: _tail,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Account or card ends in', hintText: '1234'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: HisabSpace.s12),
              Expanded(
                child: TextField(
                  key: const Key('detection-reference'),
                  controller: _reference,
                  decoration: const InputDecoration(
                      labelText: 'Reference', hintText: 'UPI ref or UTR'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SizedBox(height: HisabSpace.s16),
            AppButton(
              label: reference.isEmpty ? 'Save' : 'Add to ledger',
              size: AppButtonSize.md,
              loading: _busy,
              onPressed: canSave ? _save : null,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: HisabSpace.s24),
              Text('Could be one of these', style: HisabType.title),
              const SizedBox(height: HisabSpace.s4),
              Text('Linking keeps the bank\'s details and your category.',
                  style: HisabType.caption.copyWith(color: c.textSecondary)),
              const SizedBox(height: HisabSpace.s8),
              for (final (txn, verdict) in suggestions.take(6))
                SuggestionRow(
                  txn: txn,
                  verdict: verdict,
                  busy: _busy,
                  onLink: () => _then(() => Detections.link(
                      memo.captureHash, txn.uuid,
                      db: AppScope.of(context).db)),
                  onReject: () => Detections.reject(memo.captureHash, txn.uuid,
                      db: AppScope.of(context).db),
                ),
            ],
            const SizedBox(height: HisabSpace.s8),
            AppButton(
              label: 'Dismiss',
              size: AppButtonSize.md,
              variant: AppButtonVariant.text,
              onPressed: _busy
                  ? null
                  : () => _then(() => Detections.dismiss(memo.captureHash,
                      db: AppScope.of(context).db)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) {
      // Keep the time of day the detection had; the user picks the day.
      setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day,
          _date.hour, _date.minute, _date.second));
    }
  }

  Future<void> _save() async {
    final db = AppScope.of(context).db;
    final memo = widget.memo;
    final reference = _reference.text.trim();
    await _then(() async {
      if (_dirty) {
        await Detections.edit(memo,
            amountPaise: _paise,
            date: _date,
            payee: _payee.text,
            accountTail: _tail.text,
            db: db);
      }
      if (reference.isNotEmpty) {
        final fresh = await MemoStore.find(hash: memo.captureHash, db: db);
        if (fresh != null && fresh.mergedTxnUuid == null) {
          await Detections.promote(fresh, reference: reference, db: db);
        }
      }
    });
  }

  /// Runs one way out, then closes the sheet.
  Future<void> _then(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await Navigator.of(context).maybePop();
  }
}

/// A row the detection could be, with how sure the matcher is.
class SuggestionRow extends StatelessWidget {
  final StoredTransaction txn;
  final MatchVerdict verdict;
  final bool busy;
  final VoidCallback onLink;
  final VoidCallback onReject;

  const SuggestionRow({
    super.key,
    required this.txn,
    required this.verdict,
    required this.busy,
    required this.onLink,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.hisab;
    final likely = verdict == MatchVerdict.merge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HisabSpace.s4),
      child: Row(children: [
        StatusTag(likely ? 'Likely' : 'Possible',
            tone: likely ? HisabTone.credit : HisabTone.neutral),
        const SizedBox(width: HisabSpace.s8),
        Expanded(
          child: Text(
            '${txn.counterparty} · ${istDayLabel(dateOf(txn))} · ${sourceOf(txn).displayName}',
            overflow: TextOverflow.ellipsis,
            style: HisabType.label,
          ),
        ),
        TextButton(
          onPressed: busy ? null : onReject,
          style: TextButton.styleFrom(foregroundColor: c.textSecondary),
          child: const Text('Not this'),
        ),
        FilledButton.tonal(onPressed: busy ? null : onLink, child: const Text('Link')),
      ]),
    );
  }
}
