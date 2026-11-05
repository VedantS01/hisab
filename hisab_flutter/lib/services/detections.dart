/// Detections: money movements Hisab saw — a captured alert, text the
/// detection agent read — that are not a ledger row yet.
///
/// A detection is a pending memo with no `mergedTxnUuid`. The user completes
/// one (adds the reference, which makes it a row), links it to a row the
/// ledger already has, or dismisses it. What the user set on it — the
/// category — goes with it to the row.
library;

import 'package:drift/drift.dart';
import 'package:hisab_agents/hisab_agents.dart' show Detection;
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';
import 'import_service.dart';
import 'memo_store.dart';
import 'queries.dart';

/// A row a detection could be.
class LinkCandidate {
  final StoredTransaction txn;
  final Duration distance;
  final bool sameAmount;
  const LinkCandidate(this.txn, this.distance, this.sameAmount);
}

/// What [Detections.ingest] did with the agent's finds.
typedef IngestReport = ({int added, int waiting, int known});

abstract final class Detections {
  /// `mergedTxnUuid` of a dismissed detection: resolved, with no row. No row
  /// has this id, and a memo carrying it is never merged or shown again.
  static const dismissed = 'dismissed';

  /// Unlinked memos, latest first.
  static List<StoredPendingMemo> open(Iterable<StoredPendingMemo> memos) => [
        for (final memo in memos)
          if (memo.mergedTxnUuid == null) memo
      ]..sort((a, b) {
          final byDate = b.dateMs.compareTo(a.dateMs);
          return byDate != 0 ? byDate : b.capturedAtMs.compareTo(a.capturedAtMs);
        });

  /// Makes the memo [captureHash] the row [txnUuid]'s, and gives the row the
  /// memo's category unless the row already has one of its own.
  static Future<void> link(String captureHash, String txnUuid,
      {required AppDatabase db}) {
    return db.transaction(() async {
      final memo = await MemoStore.find(hash: captureHash, db: db);
      if (memo == null) return;
      await (db.update(db.storedPendingMemos)
            ..where((t) => t.captureHash.equals(captureHash)))
          .write(StoredPendingMemosCompanion(mergedTxnUuid: Value(txnUuid)));
      final category = memo.assignedCategory;
      if (category != null) {
        await carryCategory(txnUuid, category, db: db);
      }
    });
  }

  /// Sets [category] on the row [txnUuid] when it has none, or still has
  /// [replacing] — the category this memo gave it before.
  static Future<void> carryCategory(String txnUuid, String category,
      {String? replacing, required AppDatabase db}) async {
    await (db.update(db.storedTransactions)
          ..where((t) {
            final free = replacing == null
                ? t.categoryOverride.isNull()
                : t.categoryOverride.isNull() |
                    t.categoryOverride.equals(replacing);
            return t.uuid.equals(txnUuid) & free;
          }))
        .write(StoredTransactionsCompanion(categoryOverride: Value(category)));
  }

  /// The id of a row the ledger has for this reference and direction, from
  /// any source.
  static Future<String?> rowWith(String reference, Direction direction,
      {required AppDatabase db}) async {
    final rows = await (db.select(db.storedTransactions)
          ..where((t) =>
              t.reference.equals(reference) &
              t.direction.equals(direction.name))
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.single.uuid;
  }

  /// Rows going the same way as [memo], nearest in time first.
  static List<LinkCandidate> candidates(StoredPendingMemo memo,
      List<StoredTransaction> txns, List<StoredMatche> matches,
      {int limit = 30}) {
    final at = DateTime.fromMillisecondsSinceEpoch(memo.dateMs, isUtc: true);
    final rows = [
      for (final txn in Queries.visible(txns, matches))
        if (txn.direction == memo.direction)
          LinkCandidate(txn, dateOf(txn).difference(at).abs(),
              txn.amountPaise == memo.amountPaise)
    ]..sort((a, b) {
        final byTime = a.distance.compareTo(b.distance);
        if (byTime != 0) return byTime;
        return (b.sameAmount ? 1 : 0) - (a.sameAmount ? 1 : 0);
      });
    return rows.take(limit).toList();
  }

  /// The detection as a ledger row, with the reference the user gave, and
  /// linked to it. A reference the ledger already has links to that row.
  static Future<String> promote(StoredPendingMemo memo,
      {required String reference,
      String? counterparty,
      required AppDatabase db}) async {
    final direction = memo.directionValue;
    final payee = (counterparty ?? memo.payee).trim();
    final row = ParsedTransaction(
      date: DateTime.fromMillisecondsSinceEpoch(memo.dateMs, isUtc: true),
      amountPaise: memo.amountPaise,
      direction: direction,
      counterparty: _counterparty(payee, memo.vpa, memo.accountTail),
      reference: reference.trim(),
      narration: memo.vpa ?? '',
    );
    final id = await ImportService.insertCapturedAlert(row, db: db) ??
        (await rowWith(reference.trim(), direction, db: db))!;
    await link(memo.captureHash, id, db: db);
    return id;
  }

  static Future<void> dismiss(String captureHash, {required AppDatabase db}) =>
      (db.update(db.storedPendingMemos)
            ..where((t) => t.captureHash.equals(captureHash)))
          .write(const StoredPendingMemosCompanion(
              mergedTxnUuid: Value(dismissed)));

  /// The agent's finds in text the user gave, which arrived at [receivedAt]:
  /// each one a memo; one with a reference also a ledger row, linked.
  static Future<IngestReport> ingest(List<Detection> found,
      {required DateTime receivedAt, required AppDatabase db}) async {
    var added = 0, waiting = 0, known = 0;
    for (final d in found) {
      final memo = PendingMemo(
        amountPaise: d.amountPaise,
        direction: d.direction,
        payee: d.counterparty.isNotEmpty ? d.counterparty : (d.vpa ?? ''),
        vpa: d.vpa,
        accountTail: d.accountTail,
        date: d.date,
        capturedAt: receivedAt,
      );
      final memoNew = await MemoStore.insert(memo, db: db);
      final reference = d.reference;
      if (reference == null) {
        memoNew ? waiting++ : known++;
        continue;
      }
      final rowId = await ImportService.insertCapturedAlert(
          ParsedTransaction(
            date: d.date,
            amountPaise: d.amountPaise,
            direction: d.direction,
            counterparty: _counterparty(d.counterparty, d.vpa, d.accountTail),
            reference: reference,
            narration: d.vpa ?? '',
          ),
          db: db);
      rowId != null ? added++ : known++;
      final txn = rowId ?? await rowWith(reference, d.direction, db: db);
      if (memoNew && txn != null) await link(memo.captureHash, txn, db: db);
    }
    return (added: added, waiting: waiting, known: known);
  }

  /// Who the row is with, as `AlertCapture.ledgerRow` names it.
  static String _counterparty(String payee, String? vpa, String? tail) {
    if (payee.isNotEmpty) return payee;
    if (vpa != null && vpa.isNotEmpty) return vpa;
    return tail == null ? '' : 'A/c $tail';
  }
}
