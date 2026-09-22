/// App-wide state: the database, services, and one combined reactive
/// snapshot stream (drift watches) that every screen builds from — the
/// Flutter equivalent of iOS's @Query-driven views.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hisab_core/hisab_core.dart';

import 'services/import_service.dart';
import 'storage/database.dart';

class Snapshot {
  final List<StoredTransaction> txns;
  final List<StoredMatche> matches;
  final List<StoredCategoryRule> ruleRows;
  final List<StoredDocument> documents;
  final List<PinnedMonth> pins;

  /// EVERY memo, not only the pending ones.
  ///
  /// The review sheet looks a memo up by hash over all of them, because
  /// assigning a category is precisely what removes it from the pending set —
  /// filtering here would make a sheet blank itself the moment the user
  /// answered the question it is asking. `pendingMemos` is the filtered view
  /// the inbox and the dashboard section want.
  final List<StoredPendingMemo> memos;

  const Snapshot(this.txns, this.matches, this.ruleRows, this.documents,
      this.pins, this.memos);

  /// Unmerged, unlabelled memos, newest first — the same predicate
  /// `MemoStore.pending` applies in SQL.
  List<StoredPendingMemo> get pendingMemos {
    final rows = [
      for (final memo in memos)
        if (memo.mergedTxnUuid == null && memo.assignedCategory == null) memo
    ];
    rows.sort((a, b) => b.capturedAtMs.compareTo(a.capturedAtMs));
    return rows;
  }
}

class AppState {
  final AppDatabase db;
  final ImportService importService;
  final Ruleset ruleset;
  final InsightsConfig insightsConfig;

  /// Refreshed from InsightStore whenever the user dismisses or mutes.
  Suppressions suppressions;
  late final Stream<Snapshot> snapshots;

  /// Latest emission, replayed to late subscribers via StreamBuilder
  /// initialData — a broadcast stream alone starves tabs opened later.
  Snapshot? latest;

  AppState({
    required this.db,
    required this.importService,
    required this.ruleset,
    required this.insightsConfig,
    this.suppressions = const Suppressions(),
  }) {
    snapshots = _combine();
  }

  Stream<Snapshot> _combine() {
    late StreamController<Snapshot> controller;
    List<StoredTransaction>? txns;
    List<StoredMatche>? matches;
    List<StoredCategoryRule>? rules;
    List<StoredDocument>? documents;
    List<PinnedMonth>? pins;
    List<StoredPendingMemo>? memos;
    final subs = <StreamSubscription>[];

    void emit() {
      if (txns != null &&
          matches != null &&
          rules != null &&
          documents != null &&
          pins != null &&
          memos != null) {
        latest =
            Snapshot(txns!, matches!, rules!, documents!, pins!, memos!);
        controller.add(latest!);
      }
    }

    controller = StreamController<Snapshot>.broadcast(
      onListen: () {
        if (subs.isNotEmpty) return;
        subs.add(db.select(db.storedTransactions).watch().listen((v) {
          txns = v;
          emit();
        }));
        subs.add(db.select(db.storedMatches).watch().listen((v) {
          matches = v;
          emit();
        }));
        subs.add(db.select(db.storedCategoryRules).watch().listen((v) {
          rules = v;
          emit();
        }));
        subs.add(db.select(db.storedDocuments).watch().listen((v) {
          documents = v;
          emit();
        }));
        subs.add(db.select(db.pinnedMonths).watch().listen((v) {
          pins = v;
          emit();
        }));
        // A watch, not a one-shot fetch: a memo captured while the app is
        // open — or a category assigned from a notification button — has to
        // reach the widget tree without anything telling it to look again.
        // This is the Flutter equivalent of iOS's `@Query`.
        subs.add(db.select(db.storedPendingMemos).watch().listen((v) {
          memos = v;
          emit();
        }));
      },
    );
    return controller.stream;
  }
}

class AppScope extends InheritedWidget {
  final AppState state;
  const AppScope({super.key, required this.state, required super.child});

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.state;

  @override
  bool updateShouldNotify(AppScope oldWidget) => state != oldWidget.state;
}
