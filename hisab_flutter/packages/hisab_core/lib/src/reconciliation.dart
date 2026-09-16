/// Tiered reconciliation. Port of Reconciliation.swift.
library;

import 'domain.dart';

class ReconTxn {
  final String id;
  final DateTime date;
  final int amountPaise;
  final Direction direction;
  final String? reference;
  const ReconTxn({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.reference,
  });
}

enum MatchTier { reference, amountDate }

class MatchPair {
  final String appID;
  final String bankID;
  final MatchTier tier;
  const MatchPair(
      {required this.appID, required this.bankID, required this.tier});

  @override
  bool operator ==(Object other) =>
      other is MatchPair &&
      other.appID == appID &&
      other.bankID == bankID &&
      other.tier == tier;
  @override
  int get hashCode => Object.hash(appID, bankID, tier);
}

class ReconciliationResult {
  final List<MatchPair> matches;
  final List<String> appUnmatched;
  final List<String> bankOnly;
  const ReconciliationResult(
      {required this.matches,
      required this.appUnmatched,
      required this.bankOnly});
}

class Reconciler {
  /// Tier 1: exact reference match. Tier 2: same (amount, direction) within
  /// ±window days, closest date first; each bank txn consumed at most once.
  static ReconciliationResult reconcile({
    required List<ReconTxn> app,
    required List<ReconTxn> bank,
    int dateWindowDays = 2,
  }) {
    final matches = <MatchPair>[];
    final consumedBank = <String>{};
    final unmatchedApp = <ReconTxn>[];

    // Tier 1 — reference
    final bankByRef = <String, ReconTxn>{};
    for (final txn in bank) {
      final ref = txn.reference;
      if (ref != null && ref.isNotEmpty) {
        bankByRef.putIfAbsent(ref, () => txn);
      }
    }
    for (final txn in app) {
      final ref = txn.reference;
      final hit = (ref != null && ref.isNotEmpty) ? bankByRef[ref] : null;
      if (hit != null && !consumedBank.contains(hit.id)) {
        matches.add(
            MatchPair(appID: txn.id, bankID: hit.id, tier: MatchTier.reference));
        consumedBank.add(hit.id);
      } else {
        unmatchedApp.add(txn);
      }
    }

    // Tier 2 — amount + date window, closest first
    final window = Duration(days: dateWindowDays);
    unmatchedApp.sort((a, b) => a.date.compareTo(b.date));
    for (final txn in unmatchedApp) {
      final candidates = bank
          .where((b) =>
              !consumedBank.contains(b.id) &&
              b.amountPaise == txn.amountPaise &&
              b.direction == txn.direction &&
              b.date.difference(txn.date).abs() <= window)
          .toList()
        ..sort((l, r) {
          final dl = l.date.difference(txn.date).abs();
          final dr = r.date.difference(txn.date).abs();
          if (dl == dr) return l.date.compareTo(r.date);
          return dl.compareTo(dr);
        });
      if (candidates.isNotEmpty) {
        final hit = candidates.first;
        matches.add(
            MatchPair(appID: txn.id, bankID: hit.id, tier: MatchTier.amountDate));
        consumedBank.add(hit.id);
      }
    }

    final matchedApp = matches.map((m) => m.appID).toSet();
    return ReconciliationResult(
      matches: matches,
      appUnmatched:
          app.where((t) => !matchedApp.contains(t.id)).map((t) => t.id).toList(),
      bankOnly: bank
          .where((t) => !consumedBank.contains(t.id))
          .map((t) => t.id)
          .toList(),
    );
  }
}
