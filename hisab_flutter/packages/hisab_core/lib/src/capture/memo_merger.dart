/// Retires memos against imported statement rows.
///
/// The gates are deliberately strict and the pairing is deliberately global.
/// An unmerged memo expires harmlessly; a wrongly merged one silently moves
/// the user's note onto somebody else's payment. Port of MemoMerger.swift.
library;

import '../domain.dart';
import '../year_month.dart';
import 'pending_memo.dart';

/// A statement row a memo might turn out to be.
///
/// `id` is a `String` (not a typed UUID) to match the drift schema, where
/// transaction ids are stored as TEXT.
class MemoMergeCandidate {
  final String id;
  final DateTime date;
  final int amountPaise;
  final Direction direction;
  final String narration;

  const MemoMergeCandidate({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.narration,
  });

  @override
  bool operator ==(Object other) =>
      other is MemoMergeCandidate &&
      other.id == id &&
      other.date == date &&
      other.amountPaise == amountPaise &&
      other.direction == direction &&
      other.narration == narration;

  @override
  int get hashCode => Object.hash(id, date, amountPaise, direction, narration);
}

class _Pair {
  final String memoHash;
  final String candidateId;
  final int distance;
  const _Pair({
    required this.memoHash,
    required this.candidateId,
    required this.distance,
  });
}

class MemoMerger {
  MemoMerger._();

  static const int windowDays = 3;

  /// `captureHash -> transaction id`. Each memo and each candidate is used
  /// at most once, and the assignment is fully determined by content.
  static Map<String, String> merge({
    required List<PendingMemo> memos,
    required List<MemoMergeCandidate> candidates,
  }) {
    final pairs = <_Pair>[];
    for (final memo in memos) {
      for (final candidate in candidates) {
        if (_matches(memo, candidate)) {
          pairs.add(_Pair(
            memoHash: memo.captureHash,
            candidateId: candidate.id,
            distance: _dayGap(memo.date, candidate.date),
          ));
        }
      }
    }

    // Closest pair first. Per-memo greedy let an older memo take a nearer
    // memo's exact-date row and push that memo onto the older one's row,
    // swapping two notes between two real payments.
    pairs.sort((a, b) {
      if (a.distance != b.distance) return a.distance.compareTo(b.distance);
      if (a.memoHash != b.memoHash) return a.memoHash.compareTo(b.memoHash);
      return a.candidateId.compareTo(b.candidateId);
    });

    final claimedMemos = <String>{};
    final claimedCandidates = <String>{};
    final result = <String, String>{};
    for (final pair in pairs) {
      if (claimedMemos.contains(pair.memoHash)) continue;
      if (claimedCandidates.contains(pair.candidateId)) continue;
      claimedMemos.add(pair.memoHash);
      claimedCandidates.add(pair.candidateId);
      result[pair.memoHash] = pair.candidateId;
    }
    return result;
  }

  /// Whole IST calendar days between two instants.
  ///
  /// Truncating to the start of day is essential. Elapsed-time arithmetic
  /// borrows across midnight, so a memo captured at 23:55 and a
  /// midnight-dated statement row four date-labels later would measure as
  /// three days. `istDaysBetween` (year_month.dart) already truncates both
  /// instants to their IST calendar day before differencing, so it is safe
  /// to reuse directly here (with `.abs()` — it is signed, `dayGap` is not).
  static int _dayGap(DateTime lhs, DateTime rhs) => istDaysBetween(lhs, rhs).abs();

  /// Lowercased alphanumeric tokens. Digits are kept deliberately: a numeric
  /// VPA like `9876543210@ybl` would otherwise reduce to `{ybl}`, a subset of
  /// nearly every UPI narration, making the VPA gate a match on the bank
  /// handle alone.
  ///
  /// Combining marks (`\p{M}`) are kept alongside letters and numbers
  /// deliberately: Swift iterates extended grapheme clusters, so a
  /// Devanagari vowel sign or a decomposed Latin accent stays attached to
  /// its base letter and the cluster survives as one token. Dart has no
  /// grapheme-cluster iteration without a `characters` dependency, but a
  /// combining mark's own code point is category Mn/Mc — neither letter nor
  /// number — so without `\p{M}` it would become a separator and split the
  /// cluster in two. Keeping the mark reproduces Swift's behaviour: it never
  /// starts a token by itself in practice because bank/UPI narrations never
  /// open with a bare combining mark.
  static Set<String> tokens(String text) {
    final alnum = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(alnum.hasMatch(ch) ? ch : ' ');
    }
    return buffer
        .toString()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static bool _matches(PendingMemo memo, MemoMergeCandidate candidate) {
    if (memo.amountPaise != candidate.amountPaise) return false;
    if (memo.direction != candidate.direction) return false;
    if (_dayGap(memo.date, candidate.date) > windowDays) return false;

    final narrationTokens = tokens(candidate.narration);

    // Every part of the handle must appear, so "ram@okhdfc" does not match
    // a payment to "sriram@okhdfc".
    final vpa = memo.vpa;
    if (vpa != null) {
      final vpaTokens = tokens(vpa);
      if (vpaTokens.isNotEmpty && vpaTokens.every(narrationTokens.contains)) {
        return true;
      }
    }

    // Whole-token match. Substring containment made this gate nearly a
    // no-op for a payee whose first token is a single initial.
    final payeeTokens = memo.payeeNormalized
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    if (payeeTokens.isEmpty) return false;
    return narrationTokens.contains(payeeTokens.first);
  }
}
