/// The Detections tab: what Hisab saw that is not a ledger row yet, and the
/// three ways out — add the reference, link a row, dismiss.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hisab_agents/hisab_agents.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/apple_model.dart';
import '../services/detections.dart';
import '../services/memo_store.dart';
import '../services/queries.dart';
import '../state.dart';
import '../storage/database.dart';
import 'memo_review_sheet.dart';

DateTime _memoDate(StoredPendingMemo memo) =>
    DateTime.fromMillisecondsSinceEpoch(memo.dateMs, isUtc: true);

/// Whether this phone can run the detection agent. Asked once per process.
final Future<bool> canFindInText =
    appleModel.status().then((s) => s.ready, onError: (_) => false);

class DetectionsList extends StatelessWidget {
  final Snapshot data;
  const DetectionsList({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final open = data.detections;
    if (open.isEmpty) {
      return FutureBuilder<bool>(
        future: canFindInText,
        builder: (context, can) => EmptyState(
          icon: Icons.radar,
          title: 'No detections',
          message: 'Alerts without a reference wait here.',
          actionLabel: can.data == true ? 'Find in text' : null,
          onAction: can.data == true ? () => showFindInText(context) : null,
        ),
      );
    }
    return ListView.builder(
      itemCount: open.length,
      itemBuilder: (context, i) {
        final memo = open[i];
        final category = memo.assignedCategory;
        return TxnRow(
          leading: MerchantAvatar(name: memo.payee.isEmpty ? '?' : memo.payee),
          title: memo.payee.isEmpty ? 'Unnamed' : memo.payee,
          subtitle: [
            istDayLabel(_memoDate(memo)),
            if (memo.accountTail != null) '••${memo.accountTail}',
          ].join(' · '),
          paise: memo.amountPaise,
          tone: memo.directionValue == Direction.credit
              ? AmountTone.credit
              : AmountTone.debit,
          status: category == null
              ? null
              : StatusTag(category, tone: HisabTone.brand),
          onTap: () => showMemoReviewSheet(context, memo.captureHash),
        );
      },
    );
  }
}

/// Complete, link or dismiss one detection; shown in its review sheet.
class DetectionActions extends StatefulWidget {
  final StoredPendingMemo memo;
  final Snapshot data;
  const DetectionActions({super.key, required this.memo, required this.data});

  @override
  State<DetectionActions> createState() => _DetectionActionsState();
}

class _DetectionActionsState extends State<DetectionActions> {
  final _reference = TextEditingController();
  late final _payee = TextEditingController(text: widget.memo.payee);
  String? _linkTo;
  bool _busy = false;

  static final _referenceShape = RegExp(r'^[A-Za-z0-9]{6,}$');

  @override
  void dispose() {
    _reference.dispose();
    _payee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memo = widget.memo;
    final candidates =
        Detections.candidates(memo, widget.data.txns, widget.data.matches);
    final type = Theme.of(context).textTheme;
    final ready = _referenceShape.hasMatch(_reference.text.trim());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add to ledger', style: type.titleSmall),
        const SizedBox(height: HisabSpace.s8),
        TextField(
          key: const Key('detection-reference'),
          controller: _reference,
          decoration: const InputDecoration(
              labelText: 'Reference', hintText: 'UPI ref or UTR'),
          onChanged: (_) => setState(() {}),
        ),
        if (memo.payee.isEmpty)
          TextField(
            controller: _payee,
            decoration: InputDecoration(
                labelText: memo.directionValue == Direction.credit
                    ? 'From'
                    : 'Paid to'),
          ),
        const SizedBox(height: HisabSpace.s12),
        AppButton(
          label: 'Add',
          size: AppButtonSize.md,
          loading: _busy,
          onPressed: ready && !_busy ? _promote : null,
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: HisabSpace.s24),
          Text('Or link a transaction', style: type.titleSmall),
          const SizedBox(height: HisabSpace.s8),
          DropdownButtonFormField<String>(
            key: const Key('detection-link'),
            isExpanded: true,
            initialValue: _linkTo,
            hint: const Text('Nearest first'),
            items: [
              for (final c in candidates)
                DropdownMenuItem(
                  value: c.txn.uuid,
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${Money.formatPaise(c.txn.amountPaise)} · '
                        '${c.txn.counterparty} · '
                        '${istDayLabel(dateOf(c.txn))}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.sameAmount)
                      Icon(Icons.check_circle,
                          size: 16, color: context.hisab.credit),
                  ]),
                ),
            ],
            onChanged: (v) => setState(() => _linkTo = v),
          ),
          const SizedBox(height: HisabSpace.s12),
          AppButton(
            label: 'Link',
            size: AppButtonSize.md,
            variant: AppButtonVariant.tonal,
            onPressed: _linkTo == null || _busy ? null : _link,
          ),
        ],
        const SizedBox(height: HisabSpace.s8),
        AppButton(
          label: 'Dismiss',
          size: AppButtonSize.md,
          variant: AppButtonVariant.text,
          onPressed: _busy ? null : _dismiss,
        ),
      ],
    );
  }

  Future<void> _promote() => _then(() => Detections.promote(widget.memo,
      reference: _reference.text,
      counterparty: _payee.text,
      db: AppScope.of(context).db));

  Future<void> _link() => _then(() => Detections.link(
      widget.memo.captureHash, _linkTo!,
      db: AppScope.of(context).db));

  Future<void> _dismiss() async {
    final db = AppScope.of(context).db;
    final hash = widget.memo.captureHash;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await _then(() => Detections.dismiss(hash, db: db));
    if (messenger == null) return;
    final root = messenger.context;
    if (!root.mounted) return;
    showUndoSnackbar(root,
        message: 'Dismissed',
        onUndo: () => (db.update(db.storedPendingMemos)
              ..where((t) => t.captureHash.equals(hash)))
            .write(const StoredPendingMemosCompanion(
                mergedTxnUuid: Value(null))));
  }

  /// Runs one way out, then closes the sheet: the detection is resolved.
  Future<void> _then(Future<Object?> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await Navigator.of(context).maybePop();
  }
}

/// Paste any text — an SMS, an email, a payment history — and the detection
/// agent files what it finds.
Future<void> showFindInText(BuildContext context) => showHisabSheet<void>(
      context: context,
      title: 'Find in text',
      builder: (_) => const _FindInText(),
    );

class _FindInText extends StatefulWidget {
  const _FindInText();

  @override
  State<_FindInText> createState() => _FindInTextState();
}

class _FindInTextState extends State<_FindInText> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(HisabSpace.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(
              hintText: 'SMS, email or payment history',
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final clip = await Clipboard.getData(Clipboard.kTextPlain);
                  if (clip?.text != null) {
                    setState(() => _text.text = clip!.text!);
                  }
                },
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: HisabSpace.s12),
          AppButton(
            label: 'Find',
            icon: Icons.auto_awesome,
            loading: _busy,
            onPressed: _text.text.trim().isEmpty || _busy ? null : _find,
          ),
          if (_result != null) ...[
            const SizedBox(height: HisabSpace.s12),
            Text(_result!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Future<void> _find() async {
    final db = AppScope.of(context).db;
    setState(() {
      _busy = true;
      _result = null;
    });
    String result;
    try {
      final now = DateTime.now();
      final found = await DetectionAgent(appleModel)
          .detect(_text.text, receivedAt: now);
      result = findSummary(await Detections.ingest(found, receivedAt: now, db: db));
    } on ModelFailure catch (e) {
      result = switch (e.code) {
        'context' => 'Too long. Paste less at a time.',
        'language' => 'Only English text for now.',
        _ => "Couldn't read that.",
      };
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }
}

/// "2 added · 1 in Detections · 1 already here".
String findSummary(IngestReport report) {
  final parts = [
    if (report.added > 0) '${report.added} added',
    if (report.waiting > 0) '${report.waiting} in Detections',
    if (report.known > 0) '${report.known} already here',
  ];
  return parts.isEmpty ? 'No transactions found.' : parts.join(' · ');
}
