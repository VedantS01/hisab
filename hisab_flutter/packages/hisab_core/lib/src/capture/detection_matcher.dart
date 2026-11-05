/// Whether two sightings of money are the same payment: a detection (an
/// alert, a line the agent read) against a ledger row, or against another
/// detection.
///
/// The factors are the ones Vedant named — reference, amount, account tail
/// or card digits, time, who — and each is used only when both sides have
/// it. A reference agreeing is decisive and disagreeing is a veto; amount
/// must agree; a tail disagreeing is a veto; outside the window is a veto.
/// With no veto, a tail or a counterparty agreeing makes a merge; amount and
/// time alone make a suggestion the user confirms. On a merge the fields are
/// the union of both sides and the bank's values win conflicts
/// ([DetectionMatcher.union]).
library;

import '../domain.dart';
import '../suggestion_engine.dart';
import '../year_month.dart';

/// One side of a possible match.
class MatchSide {
  /// A memo's captureHash or a row's uuid.
  final String id;
  final int amountPaise;

  /// Null when the text didn't say which way the money went.
  final Direction? direction;
  final DateTime date;

  /// Trailing digits of the account or card, when named.
  final String? accountTail;
  final String? vpa;

  /// Who was paid or who paid, as written; empty when unknown.
  final String payee;

  /// The bank's narration for a row; empty for a detection.
  final String narration;
  final String? reference;
  final bool isLedgerRow;

  const MatchSide({
    required this.id,
    required this.amountPaise,
    required this.direction,
    required this.date,
    this.accountTail,
    this.vpa,
    this.payee = '',
    this.narration = '',
    this.reference,
    this.isLedgerRow = false,
  });

  /// Everything written about this side, as lowercase alphanumeric tokens.
  Set<String> get tokens =>
      DetectionMatcher.tokens('$payee ${vpa ?? ''} $narration');
}

enum MatchVerdict { none, suggested, merge }

class DetectionMatcher {
  DetectionMatcher._();

  /// Days apart two sightings of one payment may be: an alert dated by the
  /// bank's clock against a statement row posted a working day or two later.
  static const windowDays = 3;

  static final _alnum = RegExp(r'[a-z0-9]');
  static final _digits = RegExp(r'\d+');

  static Set<String> tokens(String text) {
    final buffer = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_alnum.hasMatch(ch) ? ch : ' ');
    }
    return buffer
        .toString()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static String? _digitsOf(String? tail) {
    if (tail == null) return null;
    return _digits.allMatches(tail).lastOrNull?.group(0);
  }

  static MatchVerdict judge(MatchSide a, MatchSide b) {
    final refA = a.reference?.trim() ?? '', refB = b.reference?.trim() ?? '';
    if (refA.isNotEmpty && refB.isNotEmpty) {
      return refA.toLowerCase() == refB.toLowerCase()
          ? MatchVerdict.merge
          : MatchVerdict.none;
    }
    if (a.amountPaise != b.amountPaise) return MatchVerdict.none;
    if (a.direction != null &&
        b.direction != null &&
        a.direction != b.direction) {
      return MatchVerdict.none;
    }
    if (istDaysBetween(a.date, b.date).abs() > windowDays) {
      return MatchVerdict.none;
    }

    var strong = false;
    final tailA = _digitsOf(a.accountTail), tailB = _digitsOf(b.accountTail);
    if (tailA != null && tailB != null) {
      // "1234" against "XX1234": the shorter is the end of the longer.
      if (!(tailA.endsWith(tailB) || tailB.endsWith(tailA))) {
        return MatchVerdict.none;
      }
      strong = true;
    } else if (tailA != null || tailB != null) {
      // A row's narration often carries the card's digits: the detection's
      // tail ending a short token there counts as the tail agreeing. Found
      // nowhere, it says nothing.
      final tail = tailA ?? tailB!;
      final text = tailA != null ? b : a;
      if (text.tokens
          .any((t) => t.endsWith(tail) && t.length <= tail.length + 4)) {
        strong = true;
      }
    }
    if (!strong) strong = _sameCounterparty(a, b);
    return strong ? MatchVerdict.merge : MatchVerdict.suggested;
  }

  /// A VPA shared whole, or every token of one side's handle in the other's
  /// text, or the first word of a name appearing whole on the other side.
  static bool _sameCounterparty(MatchSide a, MatchSide b) {
    final vpaA = a.vpa?.toLowerCase(), vpaB = b.vpa?.toLowerCase();
    if (vpaA != null && vpaB != null) return vpaA == vpaB;
    for (final (vpa, other) in [(vpaA, b), (vpaB, a)]) {
      if (vpa == null) continue;
      final parts = tokens(vpa);
      if (parts.isNotEmpty && parts.every(other.tokens.contains)) return true;
    }
    for (final (side, other) in [(a, b), (b, a)]) {
      final name = SuggestionEngine.normalize(side.payee)
          .split(' ')
          .where((s) => s.isNotEmpty);
      if (name.isEmpty) continue;
      // Whole word: "ram" is not inside "sriram"; two letters are not a name.
      final first = name.first;
      if (first.length >= 3 && other.tokens.contains(first)) return true;
    }
    return false;
  }

  /// Each detection's one merge among [candidates], each candidate claimed
  /// once, nearest in time first. A detection whose nearest merges tie
  /// between candidates gets none and shows them as suggestions instead.
  static Map<String, String> pair(
      List<MatchSide> detections, List<MatchSide> candidates) {
    final pairs = <({String detection, String candidate, int gap, int order})>[];
    for (final d in detections) {
      for (final c in candidates) {
        if (c.id == d.id) continue;
        if (judge(d, c) == MatchVerdict.merge) {
          pairs.add((
            detection: d.id,
            candidate: c.id,
            gap: c.date.difference(d.date).abs().inMinutes,
            order: pairs.length,
          ));
        }
      }
    }
    pairs.sort((x, y) =>
        x.gap != y.gap ? x.gap.compareTo(y.gap) : x.order.compareTo(y.order));
    final taken = <String>{};
    final assigned = <String, String>{};
    final ambiguous = <String>{};
    for (final p in pairs) {
      if (assigned.containsKey(p.detection) ||
          ambiguous.contains(p.detection) ||
          taken.contains(p.candidate)) {
        continue;
      }
      final rival = pairs.any((q) =>
          q != p &&
          q.detection == p.detection &&
          q.gap == p.gap &&
          !taken.contains(q.candidate));
      if (rival) {
        ambiguous.add(p.detection);
        continue;
      }
      assigned[p.detection] = p.candidate;
      taken.add(p.candidate);
    }
    return assigned;
  }

  /// Candidates worth showing for [detection], best first: merges the
  /// pairing didn't take, then suggestions, each nearest in time first.
  static List<(MatchSide, MatchVerdict)> suggestions(
      MatchSide detection, List<MatchSide> candidates) {
    final found = <(MatchSide, MatchVerdict)>[];
    for (final c in candidates) {
      if (c.id == detection.id) continue;
      final verdict = judge(detection, c);
      if (verdict != MatchVerdict.none) found.add((c, verdict));
    }
    found.sort((x, y) {
      if (x.$2 != y.$2) return x.$2 == MatchVerdict.merge ? -1 : 1;
      return x.$1.date
          .difference(detection.date)
          .abs()
          .compareTo(y.$1.date.difference(detection.date).abs());
    });
    return found;
  }

  /// The union of two sides: every field one of them has. On a conflict the
  /// bank's row wins; between two detections the one kept ([keep], the
  /// earlier) does.
  static MatchSide union(MatchSide keep, MatchSide other) {
    final bankFirst = other.isLedgerRow && !keep.isLedgerRow;
    final first = bankFirst ? other : keep;
    final second = bankFirst ? keep : other;
    return MatchSide(
      id: keep.id,
      amountPaise: first.amountPaise,
      direction: first.direction ?? second.direction,
      date: first.date,
      accountTail: first.accountTail ?? second.accountTail,
      vpa: first.vpa ?? second.vpa,
      payee: first.payee.isNotEmpty ? first.payee : second.payee,
      narration:
          first.narration.isNotEmpty ? first.narration : second.narration,
      reference: first.reference ?? second.reference,
      isLedgerRow: keep.isLedgerRow || other.isLedgerRow,
    );
  }
}
