/// Balance-chain-validated column interpretation. Port of
/// ChainInterpreter.swift — same semantics, including the two-pass opening
/// direction and the columns-vs-chain agreement rule.
library;

import '../domain.dart';
import '../money.dart';
import 'statement_date.dart';
import 'synthetic_ref.dart';

class ColumnMapping {
  final int date;
  final int narration;
  final int? reference;
  final int? debit;
  final int? credit;
  final int? amount;
  final int? drcr;
  final int balance;
  final bool amountIsUnsigned;
  final String dateFormat;
  /// Regexes with one capture group, tried against the narration when the
  /// reference cell is empty; first non-empty capture wins, else synthetic.
  final List<String> referencePatterns;

  const ColumnMapping({
    required this.date,
    required this.narration,
    this.reference,
    this.debit,
    this.credit,
    this.amount,
    this.drcr,
    required this.balance,
    this.amountIsUnsigned = false,
    required this.dateFormat,
    this.referencePatterns = const [],
  });
}

sealed class ChainOutcome {
  const ChainOutcome();
}

class ChainValidated extends ChainOutcome {
  final List<ParsedTransaction> transactions;
  const ChainValidated(this.transactions);
}

class ChainBroken extends ChainOutcome {
  final int rowIndex;
  final String detail;
  const ChainBroken(this.rowIndex, this.detail);
}

class ChainInterpreter {
  static ChainOutcome interpret({
    required List<List<String>> rows,
    required ColumnMapping mapping,
    int? openingBalancePaise,
  }) {
    final first = _run(rows, mapping, openingBalancePaise, Direction.debit);
    if (mapping.amountIsUnsigned &&
        mapping.drcr == null &&
        openingBalancePaise == null) {
      // Row 1 has no predecessor to anchor its direction; try both and let
      // the rest of the chain arbitrate.
      final second = _run(rows, mapping, null, Direction.credit);
      if (first is ChainValidated && second is ChainValidated) {
        return _sameTxns(first.transactions, second.transactions)
            ? first
            : const ChainBroken(0, 'ambiguous opening direction');
      }
      if (first is ChainValidated) return first;
      if (second is ChainValidated) return second;
      return first;
    }
    return first;
  }

  static bool _sameTxns(List<ParsedTransaction> a, List<ParsedTransaction> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ChainOutcome _run(List<List<String>> rows, ColumnMapping mapping,
      int? openingBalance, Direction openingDirection) {
    final referenceRegexes = <RegExp>[];
    for (final pattern in mapping.referencePatterns) {
      try {
        referenceRegexes.add(RegExp(pattern));
      } on FormatException {
        // ignore malformed pattern — spec lint should catch it
      }
    }

    final transactions = <ParsedTransaction>[];
    var previousBalance = openingBalance;

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      String cell(int? column) =>
          (column == null || column < 0 || column >= row.length)
              ? ''
              : row[column];

      final dateText = cell(mapping.date);
      final date = StatementDate.tryParse(dateText, mapping.dateFormat);
      if (date == null) {
        return ChainBroken(index, "unreadable date '$dateText'");
      }
      final balanceText = cell(mapping.balance);
      final balance = Money.signedPaise(balanceText);
      if (balance == null) {
        return ChainBroken(index, "unreadable balance '$balanceText'");
      }

      int amount;
      Direction? assertedDirection;
      final debitColumn = mapping.debit;
      final creditColumn = mapping.credit;
      final amountColumn = mapping.amount;
      if (debitColumn != null && creditColumn != null) {
        final debitText = cell(debitColumn);
        final creditText = cell(creditColumn);
        if (debitText.isNotEmpty && creditText.isEmpty) {
          final value = Money.signedPaise(debitText);
          if (value == null) {
            return ChainBroken(index, "unreadable debit '$debitText'");
          }
          amount = value;
          assertedDirection = Direction.debit;
        } else if (debitText.isEmpty && creditText.isNotEmpty) {
          final value = Money.signedPaise(creditText);
          if (value == null) {
            return ChainBroken(index, "unreadable credit '$creditText'");
          }
          amount = value;
          assertedDirection = Direction.credit;
        } else {
          return ChainBroken(index,
              "expected exactly one of debit/credit, got '$debitText'/'$creditText'");
        }
      } else if (amountColumn != null) {
        final amountText = cell(amountColumn);
        final value = Money.signedPaise(amountText);
        if (value == null) {
          return ChainBroken(index, "unreadable amount '$amountText'");
        }
        final drcrColumn = mapping.drcr;
        if (drcrColumn != null) {
          switch (cell(drcrColumn).toLowerCase()) {
            case 'dr':
              assertedDirection = Direction.debit;
            case 'cr':
              assertedDirection = Direction.credit;
            default:
              return ChainBroken(
                  index, "unreadable DR/CR '${cell(drcrColumn)}'");
          }
          amount = value.abs();
        } else if (mapping.amountIsUnsigned) {
          amount = value.abs();
          assertedDirection = null;
        } else {
          amount = value.abs();
          assertedDirection =
              value < 0 ? Direction.debit : Direction.credit;
        }
      } else {
        return ChainBroken(index, 'mapping declares no amount columns');
      }

      if (amount <= 0) {
        return ChainBroken(index, 'non-positive amount');
      }

      Direction direction;
      final previous = previousBalance;
      if (previous != null) {
        if (previous - amount == balance) {
          direction = Direction.debit;
        } else if (previous + amount == balance) {
          direction = Direction.credit;
        } else {
          return ChainBroken(
              index, 'balance chain break: $previous ±$amount ≠ $balance');
        }
        if (assertedDirection != null && assertedDirection != direction) {
          return ChainBroken(index,
              'columns say ${assertedDirection.name}, chain says ${direction.name}');
        }
      } else {
        direction = assertedDirection ?? openingDirection;
      }

      final narration = cell(mapping.narration);
      final referenceCell = cell(mapping.reference);
      String reference;
      if (referenceCell.isNotEmpty) {
        reference = referenceCell;
      } else {
        final extracted = _extractReference(narration, referenceRegexes);
        reference = extracted ??
            SyntheticRef.make(
                balancePaise: balance, date: date, amountPaise: amount);
      }
      transactions.add(ParsedTransaction(
        date: date,
        amountPaise: amount,
        direction: direction,
        counterparty: narration,
        reference: reference,
        narration: narration,
      ));
      previousBalance = balance;
    }

    return ChainValidated(transactions);
  }

  static String? _extractReference(String narration, List<RegExp> regexes) {
    for (final regex in regexes) {
      final match = regex.firstMatch(narration);
      if (match == null || match.groupCount < 1) continue;
      final captured = match.group(1)?.trim() ?? '';
      if (captured.isNotEmpty) return captured;
    }
    return null;
  }
}
