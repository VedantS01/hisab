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
  const Snapshot(
      this.txns, this.matches, this.ruleRows, this.documents, this.pins);
}

class AppState {
  final AppDatabase db;
  final ImportService importService;
  final Ruleset ruleset;
  late final Stream<Snapshot> snapshots;

  /// Latest emission, replayed to late subscribers via StreamBuilder
  /// initialData — a broadcast stream alone starves tabs opened later.
  Snapshot? latest;

  AppState({required this.db, required this.importService, required this.ruleset}) {
    snapshots = _combine();
  }

  Stream<Snapshot> _combine() {
    late StreamController<Snapshot> controller;
    List<StoredTransaction>? txns;
    List<StoredMatche>? matches;
    List<StoredCategoryRule>? rules;
    List<StoredDocument>? documents;
    List<PinnedMonth>? pins;
    final subs = <StreamSubscription>[];

    void emit() {
      if (txns != null &&
          matches != null &&
          rules != null &&
          documents != null &&
          pins != null) {
        latest = Snapshot(txns!, matches!, rules!, documents!, pins!);
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
