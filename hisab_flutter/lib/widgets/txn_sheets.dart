/// The transaction sheets Home and Transactions share: one row's detail with
/// its category chips, a list of rows (a merchant's or a category's month),
/// and the category picker multi-select uses.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:hisab_core/hisab_core.dart';

import '../design/design.dart';
import '../services/queries.dart';
import '../storage/database.dart';
import '../state.dart';
import 'memo_review_sheet.dart' show istStamp;

/// Every category a row can be given, Uncategorized (which clears an
/// override) included.
List<String> categoryOptions(List<CategoryRule> rules) => {
  for (final rule in rules) rule.category,
  Categorizer.uncategorized,
}.toList()..sort();

/// Sets (or, for Uncategorized, clears) the category override on [uuids].
Future<void> setCategory(
  AppDatabase db,
  Iterable<String> uuids,
  String option,
) async {
  await (db.update(
    db.storedTransactions,
  )..where((t) => t.uuid.isIn(uuids.toList()))).write(
    StoredTransactionsCompanion(
      categoryOverride: Value(
        option == Categorizer.uncategorized ? null : option,
      ),
    ),
  );
}

/// One category, picked from chips; null when dismissed.
Future<String?> pickCategory(
  BuildContext context,
  List<String> options, {
  String? current,
  String title = 'Category',
}) => showHisabSheet<String>(
  context: context,
  title: title,
  builder: (context) => SingleChildScrollView(
    child: Wrap(
      spacing: HisabSpace.s8,
      runSpacing: HisabSpace.s8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: option == current,
            onSelected: (_) => Navigator.pop(context, option),
          ),
      ],
    ),
  ),
);

/// The day, with the time when the row has one (statement rows are dated to
/// the day, IST midnight; captured alerts and app exports carry a time).
String _when(DateTime date) {
  final clock = istClock(date);
  return clock.hour == 0 && clock.minute == 0
      ? istDayString(date)
      : istStamp(date);
}

void showTxnDetail(
  BuildContext context,
  StoredTransaction txn,
  String category,
  List<CategoryRule> ruleList,
) {
  final state = AppScope.of(context);
  final categories = categoryOptions(ruleList);
  showHisabSheet<void>(
    context: context,
    builder: (context) => SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  txn.counterparty,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              AmountText(
                txn.amountPaise,
                role: AmountRole.md,
                tone: directionOf(txn) == Direction.credit
                    ? AmountTone.credit
                    : AmountTone.debit,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('${sourceOf(txn).displayName} · ${_when(dateOf(txn))}'),
          if (txn.reference != null)
            Text(
              'Ref: ${txn.reference}',
              style: TextStyle(
                fontSize: 12,
                color: context.hisab.textSecondary,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            txn.narration,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.hisab.textSecondary),
          ),
          const Divider(height: 24),
          const Text('Category', style: TextStyle(fontWeight: FontWeight.w600)),
          Wrap(
            spacing: 8,
            children: [
              for (final option in categories)
                ChoiceChip(
                  label: Text(option),
                  selected: option == category,
                  onSelected: (_) async {
                    await setCategory(state.db, [txn.uuid], option);
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// A drawer of rows, newest first, each opening [showTxnDetail]. Rows are
/// re-read from the live snapshot, so a category changed from the detail
/// shows here when the detail closes.
void showTxnListSheet(
  BuildContext context, {
  required String title,
  required bool Function(StoredTransaction txn, String category) where,
}) {
  final state = AppScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => StreamBuilder<Snapshot>(
        initialData: state.latest,
        stream: state.snapshots,
        builder: (context, snap) {
          final data = snap.data;
          if (data == null) return const SizedBox.shrink();
          final ruleList = Queries.rules(data.ruleRows);
          final matcher = CategoryMatcher(ruleList);
          final self = Queries.selfTransferUuids(data.txns);
          final rows =
              [
                  for (final txn in Queries.visible(data.txns, data.matches))
                    if (!self.contains(txn.uuid))
                      (txn, Queries.effectiveCategory(txn, matcher, self)),
                ].where((r) => where(r.$1, r.$2)).toList()
                ..sort((a, b) => b.$1.dateMs.compareTo(a.$1.dateMs));
          final total = rows.fold<int>(0, (a, r) => a + r.$1.amountPaise);
          return ListView.builder(
            controller: scroll,
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HisabSpace.gutter,
                    HisabSpace.s4,
                    HisabSpace.gutter,
                    HisabSpace.s8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: HisabType.title.copyWith(
                            color: context.hisab.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${rows.length} · ',
                        style: HisabType.caption.copyWith(
                          color: context.hisab.textSecondary,
                        ),
                      ),
                      AmountText(total, role: AmountRole.md),
                    ],
                  ),
                );
              }
              final (txn, category) = rows[i - 1];
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
                onTap: () => showTxnDetail(context, txn, category, ruleList),
              );
            },
          );
        },
      ),
    ),
  );
}
