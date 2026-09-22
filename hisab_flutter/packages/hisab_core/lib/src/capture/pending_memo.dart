/// A transaction alert Hisab captured but has NOT admitted to the ledger.
///
/// Alerts carry no UTR, so they cannot join content-hash dedup or
/// balance-chain validation — the two properties that make Hisab's numbers
/// trustworthy. A memo's durable output is a categorization *rule*; the
/// statement remains the single source of truth. Port of PendingMemo.swift.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';

enum RuleKeyKind { vpa, merchant }

/// What a rule written from a memo should match on. The VPA is preferred
/// because personal-name payees render inconsistently across statements
/// ("VEDANT SABOO", "Vedant S", "UPI/1234/VEDANT") while `name@handle` does
/// not — and UPI narrations carry the VPA verbatim, so the longest-match
/// matcher will pick it.
class RuleKey {
  final String pattern;
  final RuleKeyKind kind;
  const RuleKey({required this.pattern, required this.kind});

  @override
  bool operator ==(Object other) =>
      other is RuleKey && other.pattern == pattern && other.kind == kind;

  @override
  int get hashCode => Object.hash(pattern, kind);

  @override
  String toString() => 'RuleKey($pattern, $kind)';
}

class PendingMemo {
  final int amountPaise;
  final Direction direction;

  /// As it appeared in the alert, for display.
  final String payee;

  /// VPA in full (`name@handle`), lowercased, when the alert carried one.
  final String? vpa;

  /// Trailing digits of the account the alert named, e.g. "1234".
  final String? accountTail;

  /// The transaction's own date (the alert's, or capture time if absent).
  final DateTime date;
  final DateTime capturedAt;
  final String? note;

  PendingMemo({
    required this.amountPaise,
    required this.direction,
    required this.payee,
    String? vpa,
    this.accountTail,
    required this.date,
    required this.capturedAt,
    this.note,
  }) : vpa = vpa?.toLowerCase();

  /// Value equality over stored fields only, matching Swift's synthesized
  /// `Equatable` conformance — the computed properties (`payeeNormalized`,
  /// `captureHash`, `ruleKey`) are derived and deliberately excluded.
  @override
  bool operator ==(Object other) =>
      other is PendingMemo &&
      other.amountPaise == amountPaise &&
      other.direction == direction &&
      other.payee == payee &&
      other.vpa == vpa &&
      other.accountTail == accountTail &&
      other.date == date &&
      other.capturedAt == capturedAt &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
      amountPaise, direction, payee, vpa, accountTail, date, capturedAt, note);

  /// Cluster key shared with the suggestion engine so a rule written here
  /// matches patterns the rule store already contains.
  String get payeeNormalized => SuggestionEngine.normalize(payee);

  /// Stable identity. Two captures of one payment collapse; a refund of the
  /// same amount to the same payee stays distinct (direction is in the key).
  String get captureHash {
    final canonical = [
      amountPaise.toString(),
      direction.name,
      payeeNormalized,
      vpa ?? '',
      istDayString(date),
    ].join('|');
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  RuleKey get ruleKey {
    final v = vpa;
    if (v != null && v.length >= 3) {
      return RuleKey(pattern: v, kind: RuleKeyKind.vpa);
    }
    return RuleKey(pattern: payeeNormalized, kind: RuleKeyKind.merchant);
  }
}
