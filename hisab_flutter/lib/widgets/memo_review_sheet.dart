/// One captured alert, and the categorization that turns it into a rule.
/// Twin of `Hisab/Views/MemoReviewSheet.swift`.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../services/capture_notifier.dart';
import '../services/memo_store.dart';
import '../services/queries.dart';
import '../state.dart';
import '../storage/database.dart';
import '../theme.dart';

/// "22 Sep 2026, 4:18 PM IST".
///
/// Spelled out because it is deliberately NOT the device's clock: the capture
/// hash is keyed on the IST day, so a phone that has travelled must not show a
/// capture on a different day from the one its own identity was built from.
String istStamp(DateTime date) {
  final clock = istClock(date);
  final hour24 = clock.hour;
  final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = clock.minute.toString().padLeft(2, '0');
  final meridiem = hour24 < 12 ? 'AM' : 'PM';
  return '${istDayLabel(date)}, $hour:$minute $meridiem IST';
}

/// The one place a proposed rule is measured and written.
///
/// Both the review sheet and the queued-offer sheet go through here, so the
/// number the user is shown and the rule that lands come from the same code on
/// both paths.
class RuleOffers {
  RuleOffers._();

  /// How many recorded transactions the proposed rule would really move.
  ///
  /// [RuleImpact.affectedCount] simulates the matcher on both sides, so this
  /// is exact by construction for the rows it is given; [Queries.impactRows]
  /// is where the row population and the two exclusion flags are decided.
  static int affectedCount({
    required String pattern,
    required String category,
    required Snapshot data,
  }) {
    final selfTransfers = Queries.selfTransferUuids(data.txns);
    return RuleImpact.affectedCount(
      pattern: pattern,
      category: category,
      rows: Queries.impactRows(data.txns, data.matches, selfTransfers),
      rules: Queries.rules(data.ruleRows),
    );
  }

  /// Writes the accepted rule, following `showSuggestionPrompt`: the new rule
  /// takes the highest `sortOrder`.
  ///
  /// That is not cosmetic. [RuleImpact.affectedCount] APPENDS the proposed
  /// rule when it simulates, and [CategoryMatcher] breaks a same-length tie by
  /// lowest rule index — so a rule stored anywhere but the end could lose or
  /// win a tie the count did not predict, and the promise would be wrong for
  /// exactly the rows a tie decides.
  ///
  /// No backfill loop: [Queries.effectiveCategory] derives a category at read
  /// time, so every matching row changes the moment the rule is saved.
  static Future<void> createRule({
    required String pattern,
    required String category,
    required AppDatabase db,
  }) async {
    final rows = await db.select(db.storedCategoryRules).get();
    final order = rows.isEmpty
        ? 0
        : rows.map((r) => r.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await db.into(db.storedCategoryRules).insert(
        StoredCategoryRulesCompanion.insert(
            id: newId(),
            pattern: pattern,
            category: category,
            sortOrder: order));
  }
}

/// A measured offer, ready to show. `count` is fixed at the moment the
/// category was chosen so the sentence cannot change under the user's finger.
@immutable
class MeasuredOffer {
  final String captureHash;
  final String pattern;
  final String category;
  final int count;
  const MeasuredOffer({
    required this.captureHash,
    required this.pattern,
    required this.category,
    required this.count,
  });
}

/// Opens the review sheet for one memo. The single presentation path, so a
/// memo reached from a notification, the dashboard section or the inbox all
/// land on the same screen.
Future<void> showMemoReviewSheet(
    BuildContext context, String captureHash) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: MemoReviewContent(captureHash: captureHash),
    ),
  );
}

class MemoReviewContent extends StatefulWidget {
  final String captureHash;
  const MemoReviewContent({super.key, required this.captureHash});

  @override
  State<MemoReviewContent> createState() => _MemoReviewContentState();
}

class _MemoReviewContentState extends State<MemoReviewContent> {
  final _note = TextEditingController();

  /// Which memo [_note] was loaded for, so a rebuild never clobbers what the
  /// user is typing and a different memo never inherits it.
  String? _noteLoadedFor;
  MeasuredOffer? _offer;
  bool _ruleSaved = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return StreamBuilder<Snapshot>(
      initialData: state.latest,
      stream: state.snapshots,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        StoredPendingMemo? memo;
        for (final row in data.memos) {
          if (row.captureHash == widget.captureHash) memo = row;
        }
        return Scaffold(
          backgroundColor: HisabTheme.kagaz,
          appBar: AppBar(
            title: const Text('Review alert'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Done')),
            ],
          ),
          body: memo == null ? _gone() : _form(data, memo),
        );
      },
    );
  }

  Widget _gone() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox, size: 48, color: Colors.black26),
              const SizedBox(height: 12),
              const Text('This memo is gone.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                  'It was merged into a statement row, or it expired after '
                  '${PendingMemo.expiryDays} days.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );

  Widget _form(Snapshot data, StoredPendingMemo memo) {
    _loadNote(memo);
    final offer = _offer;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Amount',
                        style: TextStyle(color: Colors.black54)),
                    Text(Money.formatPaise(memo.amountPaise),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: HisabTheme.amountColor(
                                memo.directionValue))),
                  ],
                ),
                const SizedBox(height: 6),
                _line('Payee', memo.payee),
                if (memo.vpa != null) _line('UPI ID', memo.vpa!),
                if (memo.accountTail != null)
                  _line('Account', '••${memo.accountTail}'),
                _line('Captured',
                    istStamp(DateTime.fromMillisecondsSinceEpoch(
                        memo.capturedAtMs,
                        isUtc: true))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Optional — what was this for?',
          ),
          maxLines: 3,
          minLines: 1,
          onChanged: (_) => _saveNote(memo),
        ),
        const SizedBox(height: 16),
        const Text('Category',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const Text(
            'The first few are what you spend on most; the rest are every '
            'category your rules already use. Nothing here touches your '
            'statements — a memo is a label, not a ledger entry.',
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final category in _categoryChoices(data))
                ListTile(
                  dense: true,
                  title: Text(category),
                  trailing: memo.assignedCategory == category
                      ? const Icon(Icons.check, color: HisabTheme.khataRed)
                      : null,
                  onTap: () => _assign(data, memo, category),
                ),
            ],
          ),
        ),
        if (offer != null) ...[
          const SizedBox(height: 12),
          _offerCard(data, offer),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.black54)),
            Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  Widget _offerCard(Snapshot data, MeasuredOffer offer) => Card(
        key: const Key('memo-rule-offer'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Remember this?',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 6),
              if (_ruleSaved)
                Row(children: [
                  const Icon(Icons.check_circle,
                      color: HisabTheme.hara, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(offer.count == 0
                          ? 'Rule saved. No past transactions matched.'
                          : 'Rule saved. ${_countPhrase(offer.count)} '
                              're-categorized.')),
                ])
              else ...[
                Text('Always categorize “${offer.pattern}” as '
                    '${offer.category}?',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (offer.count > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'This will also update ${_countPhrase(offer.count)}.',
                        style: const TextStyle(color: Colors.black54)),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await CaptureNotifier.clearOffer(offer.captureHash);
                        if (mounted) setState(() => _offer = null);
                      },
                      child: const Text('Not now',
                          style: TextStyle(color: Colors.black54)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: HisabTheme.khataRed),
                      onPressed: () async {
                        await RuleOffers.createRule(
                            pattern: offer.pattern,
                            category: offer.category,
                            db: AppScope.of(context).db);
                        await CaptureNotifier.clearOffer(offer.captureHash);
                        if (mounted) setState(() => _ruleSaved = true);
                      },
                      child: const Text('Create rule'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  static String _countPhrase(int count) =>
      '$count past ${count == 1 ? 'transaction' : 'transactions'}';

  /// [CategoryRanker]'s three, then every other category the user's rules
  /// already use, alphabetically. The reserved names are not choices: two of
  /// them mean "no answer" and the third is assigned by reconciliation.
  List<String> _categoryChoices(Snapshot data) {
    final state = AppScope.of(context);
    final matcher = Queries.matcher(data.ruleRows);
    final ranked = CategoryRanker.topCategories(
      records: Queries.suggestionRecords(data.txns, data.matches, matcher),
      now: DateTime.now(),
      limit: 3,
      ruleset: state.ruleset,
    );
    const reserved = {
      Categorizer.uncategorized,
      Categorizer.miscellaneous,
      Categorizer.selfTransfer,
    };
    final seen = {...ranked};
    final rest = [
      for (final row in data.ruleRows)
        if (!reserved.contains(row.category) && seen.add(row.category))
          row.category
    ]..sort();
    return [...ranked, ...rest];
  }

  void _loadNote(StoredPendingMemo memo) {
    if (_noteLoadedFor == widget.captureHash) return;
    _noteLoadedFor = widget.captureHash;
    _note.text = memo.note ?? '';
  }

  Future<void> _saveNote(StoredPendingMemo memo) async {
    final db = AppScope.of(context).db;
    final trimmed = _note.text.trim();
    final value = trimmed.isEmpty ? null : trimmed;
    if (memo.note == value) return;
    await (db.update(db.storedPendingMemos)
          ..where((t) => t.captureHash.equals(memo.captureHash)))
        .write(StoredPendingMemosCompanion(note: Value(value)));
  }

  Future<void> _assign(
      Snapshot data, StoredPendingMemo memo, String category) async {
    final db = AppScope.of(context).db;
    await _saveNote(memo);
    await MemoStore.assign(category: category, memo: memo, db: db);
    final pattern = memo.asMemo.ruleKey.pattern;
    if (pattern.isEmpty) {
      if (mounted) setState(() => _offer = null);
      return;
    }
    final count = RuleOffers.affectedCount(
        pattern: pattern, category: category, data: data);
    // An offer the user is looking at supersedes one this memo queued from a
    // notification button; leaving both would ask the same question twice.
    await CaptureNotifier.clearOffer(memo.captureHash);
    if (!mounted) return;
    setState(() {
      _ruleSaved = false;
      _offer = MeasuredOffer(
          captureHash: memo.captureHash,
          pattern: pattern,
          category: category,
          count: count);
    });
  }
}

/// The rule offer for a category chosen from a NOTIFICATION button, shown the
/// next time Hisab is opened.
///
/// A category button assigns immediately, but the question — "should this
/// become a rule?" — has nowhere to be asked at that moment.
/// `CaptureNotifier.pendingRuleOffers` holds it until here.
Future<void> showQueuedRuleOffer(BuildContext context, RuleOffer offer) async {
  final state = AppScope.of(context);
  final data = state.latest;
  if (data == null) return;
  StoredPendingMemo? memo;
  for (final row in data.memos) {
    if (row.captureHash == offer.captureHash) memo = row;
  }
  final pattern = memo?.asMemo.ruleKey.pattern ?? '';
  final count = pattern.isEmpty
      ? 0
      : RuleOffers.affectedCount(
          pattern: pattern, category: offer.category, data: data);
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: const Key('queued-rule-offer'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fact_check, size: 40, color: HisabTheme.sona),
            const SizedBox(height: 12),
            Text(
                memo == null
                    ? 'You filed a payment as ${offer.category}.'
                    : 'You filed ${Money.formatPaise(memo.amountPaise)} to '
                        '${memo.payee} as ${offer.category}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (pattern.isEmpty)
              const Text(
                  'That memo is gone, so there is nothing left to build a '
                  'rule from.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54))
            else ...[
              Text('Always categorize “$pattern” as ${offer.category}?',
                  textAlign: TextAlign.center),
              if (count > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'This will also update $count past '
                      '${count == 1 ? 'transaction' : 'transactions'}.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: HisabTheme.khataRed),
                onPressed: () async {
                  await RuleOffers.createRule(
                      pattern: pattern,
                      category: offer.category,
                      db: state.db);
                  await CaptureNotifier.clearOffer(offer.captureHash);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Create rule'),
              ),
            ],
            TextButton(
              onPressed: () async {
                await CaptureNotifier.clearOffer(offer.captureHash);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(pattern.isEmpty ? 'OK' : 'Not now',
                  style: const TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      ),
    ),
  );
}
