/// Cross-bank self-transfer detection. Port of SelfTransfers.swift.
library;

import 'domain.dart';
import 'reconciliation.dart';

class BankTxn {
  final ReconTxn txn;
  final Source source;
  const BankTxn(this.txn, this.source);
}

class SelfTransfers {
  /// A debit in one bank source paired with an equal credit in a *different*
  /// bank source within the date window. Both sides are internal movements.
  static Set<String> detect(List<BankTxn> bank, {int dateWindowDays = 2}) {
    final window = Duration(days: dateWindowDays);
    final debits = bank.where((b) => b.txn.direction == Direction.debit).toList()
      ..sort((a, b) => a.txn.date.compareTo(b.txn.date));
    final credits =
        bank.where((b) => b.txn.direction == Direction.credit).toList();
    final flagged = <String>{};

    for (final debit in debits) {
      BankTxn? best;
      var bestIndex = -1;
      Duration? bestDelta;
      for (var i = 0; i < credits.length; i++) {
        final credit = credits[i];
        if (credit.source == debit.source) continue;
        if (credit.txn.amountPaise != debit.txn.amountPaise) continue;
        final delta = credit.txn.date.difference(debit.txn.date).abs();
        if (delta > window) continue;
        if (bestDelta == null || delta < bestDelta) {
          best = credit;
          bestIndex = i;
          bestDelta = delta;
        }
      }
      if (best != null) {
        flagged.add(debit.txn.id);
        flagged.add(best.txn.id);
        credits.removeAt(bestIndex);
      }
    }
    return flagged;
  }

  /// Captured-alert rows ([Source.alert]) that are legs of a transfer between
  /// the user's own accounts. Alert rows are payment-app side, so [detect]
  /// never sees them; without this, one transfer alerted on both accounts
  /// would count as spending and as income.
  ///
  /// A row is a self transfer when another alert row has the same reference
  /// and the opposite direction (one IMPS ref appears in the sending bank's
  /// debit alert and the receiving bank's credit alert), or when its
  /// reference is on a bank row [detect] already flagged.
  static Set<String> alerts(
      List<({String id, String reference, Direction direction})> rows,
      {required Set<String> bankSelfTransferRefs}) {
    final directions = <String, Set<Direction>>{};
    for (final row in rows) {
      (directions[row.reference] ??= {}).add(row.direction);
    }
    return {
      for (final row in rows)
        if (directions[row.reference]?.length == 2 ||
            bankSelfTransferRefs.contains(row.reference))
          row.id
    };
  }
}
