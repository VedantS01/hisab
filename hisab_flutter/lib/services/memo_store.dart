/// Drift shim for pending memos. Deliberately logic-free — the twin of
/// Hisab/Services/MemoStore.swift, method-for-method.
///
/// Dates are stored as millisecond epochs (`dateMs`, `capturedAtMs`,
/// `notifiedAtMs`), following the existing table convention. Money stays
/// integer paise. The raw alert text is never written anywhere.
library;

import 'package:drift/drift.dart';
import 'package:hisab_core/hisab_core.dart';

import '../storage/database.dart';

int _ms(DateTime date) => date.toUtc().millisecondsSinceEpoch;

DateTime _date(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

/// `StoredPendingMemo.asMemo` from the Swift model, as an extension because
/// the drift row class is generated.
extension StoredPendingMemoConversion on StoredPendingMemo {
  Direction get directionValue =>
      direction == 'credit' ? Direction.credit : Direction.debit;

  PendingMemo get asMemo => PendingMemo(
        amountPaise: amountPaise,
        direction: directionValue,
        payee: payee,
        vpa: vpa,
        accountTail: accountTail,
        date: _date(dateMs),
        capturedAt: _date(capturedAtMs),
        note: note,
      );
}

class MemoStore {
  MemoStore._();

  /// False when this alert was already captured — the dedup guard that stops
  /// Android's notification *updates* producing a second memo.
  ///
  /// The lookup and the write share one transaction, so the guard cannot be
  /// straddled by another capture on the same connection. An upsert is
  /// deliberately NOT used: it would overwrite a memo the user has already
  /// categorized (dropping `assignedCategory`, `mergedTxnUuid`,
  /// `notifiedAtMs`) every time the same alert is re-posted. Declining the
  /// capture is the cheaper error, exactly as on iOS.
  static Future<bool> insert(PendingMemo memo, {required AppDatabase db}) {
    return db.transaction(() async {
      final existing = await find(hash: memo.captureHash, db: db);
      if (existing != null) return false;
      await db.into(db.storedPendingMemos).insert(
            StoredPendingMemosCompanion.insert(
              captureHash: memo.captureHash,
              amountPaise: memo.amountPaise,
              direction: memo.direction.name,
              payee: memo.payee,
              payeeNormalized: memo.payeeNormalized,
              vpa: Value(memo.vpa),
              accountTail: Value(memo.accountTail),
              dateMs: _ms(memo.date),
              capturedAtMs: _ms(memo.capturedAt),
              note: Value(memo.note),
            ),
          );
      return true;
    });
  }

  /// Unmerged, unlabelled memos, newest first.
  static Future<List<StoredPendingMemo>> pending(AppDatabase db) {
    final query = db.select(db.storedPendingMemos)
      ..where((t) => t.mergedTxnUuid.isNull() & t.assignedCategory.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.capturedAtMs, mode: OrderingMode.desc)
      ]);
    return query.get();
  }

  static Future<List<StoredPendingMemo>> all(AppDatabase db) =>
      db.select(db.storedPendingMemos).get();

  static Future<StoredPendingMemo?> find({
    required String hash,
    required AppDatabase db,
  }) {
    final query = db.select(db.storedPendingMemos)
      ..where((t) => t.captureHash.equals(hash));
    return query.getSingleOrNull();
  }

  static Future<void> assign({
    required String category,
    required StoredPendingMemo memo,
    required AppDatabase db,
  }) async {
    final update = db.update(db.storedPendingMemos)
      ..where((t) => t.captureHash.equals(memo.captureHash));
    await update.write(
        StoredPendingMemosCompanion(assignedCategory: Value(category)));
  }

  /// Drops memos no statement is going to retire. A merged memo is kept: it
  /// records that a ledger row was seen live, and deleting it would let the
  /// same alert be captured again.
  static Future<void> expire({
    required DateTime now,
    required AppDatabase db,
  }) async {
    final doomed = [
      for (final memo in await all(db))
        if (memo.mergedTxnUuid == null &&
            PendingMemo.isExpired(
                capturedAt: _date(memo.capturedAtMs), now: now))
          memo.captureHash
    ];
    if (doomed.isEmpty) return;
    final delete = db.delete(db.storedPendingMemos)
      ..where((t) => t.captureHash.isIn(doomed));
    await delete.go();
  }
}
