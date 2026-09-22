/// Reads a bank/UPI transaction alert into a `PendingMemo`, or declines.
///
/// Every rule here is deliberately conservative. `null` means "this was not
/// confidently a single money movement", and callers drop the alert silently.
/// A false memo trains a categorization rule on a payment that never
/// happened, which is far worse than missing one. Port of AlertParser.swift.
library;

import '../domain.dart';
import '../money.dart';
import '../year_month.dart';
import 'pending_memo.dart';

class _AmountHit {
  final int paise;
  final int end;
  const _AmountHit(this.paise, this.end);
}

class AlertParser {
  AlertParser._();

  static const List<String> _debitWords = [
    'debited', 'spent', 'withdrawn', 'paid', 'sent', 'purchase',
  ];
  static const List<String> _creditWords = [
    'credited', 'received', 'refund', 'deposited',
  ];

  static PendingMemo? parse(String text, DateTime receivedAt) {
    final collapsed = text
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .join(' ');
    final lower = collapsed.toLowerCase();

    final direction = _direction(lower);
    if (direction == null) return null;
    final amount = _amount(lower);
    if (amount == null || amount.paise <= 0) return null;
    final vpa = _vpa(lower);
    final extracted =
        _payee(collapsed, lower, direction, amount.end);
    final payee = extracted ?? (vpa != null ? vpa.split('@')[0] : null);
    if (payee == null || payee.isEmpty) return null;

    return PendingMemo(
      amountPaise: amount.paise,
      direction: direction,
      payee: payee,
      vpa: vpa,
      accountTail: _accountTail(lower),
      date: _date(lower) ?? receivedAt,
      capturedAt: receivedAt,
    );
  }

  /// Exactly one direction must be present. Both means a summary or an ad;
  /// neither means a balance notice.
  static Direction? _direction(String lower) {
    final debit = _debitWords.any(lower.contains);
    final credit = _creditWords.any(lower.contains);
    if (debit && !credit) return Direction.debit;
    if (credit && !debit) return Direction.credit;
    return null;
  }

  /// The amount and where it ended. The end position anchors payee extraction:
  /// the amount is the one landmark guaranteed to sit inside the transaction
  /// clause, whereas a direction keyword ("sent", "paid") turns up in template
  /// preambles and would let a disclaimer's " to " win.
  static _AmountHit? _amount(String lower) {
    final hit = _firstAmount(
        r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)', lower);
    if (hit != null) return hit;
    return _firstAmount(r'(?<![0-9.])([0-9][0-9,]*\.[0-9]{2})(?![0-9.])', lower);
  }

  static _AmountHit? _firstAmount(String pattern, String lower) {
    final regex = RegExp(pattern);
    final match = regex.firstMatch(lower);
    if (match == null) return null;
    final captured = match.group(1);
    if (captured == null) return null;
    final paise = Money.signedPaise(captured);
    if (paise == null) return null;
    return _AmountHit(paise, match.end);
  }

  /// A VPA handle has no dot; an email domain does. That single distinction
  /// keeps support addresses out of the rule key.
  static String? _vpa(String lower) {
    final regex =
        RegExp(r'([a-z0-9][a-z0-9._-]{1,})@([a-z]{2,})(?![a-z0-9-])(?!\.[a-z])');
    return regex.firstMatch(lower)?.group(0);
  }

  static const List<String> _debitLeadIns = [
    ' to vpa ', ' vpa ', ' to ', ' at ', ' towards ',
  ];
  static const List<String> _creditLeadIns = [' from ', ' by '];

  /// Tokens that always end a payee. Each one is boilerplate that is never a
  /// word in a merchant's name. Deliberately SHORT: a stop token that collides
  /// with a real name either truncates the payee into a generic rule key or
  /// drops the alert entirely, and both are worse than leaving a reference
  /// fragment attached.
  static const Set<String> _payeeStopTokens = {
    'ref', 'refno', 'utr', 'txn', 'upi', 'a/c', 'acct', 'account',
    'avl', 'dated', 'using', 'thru', 'through', 'vide', 'via',
  };

  /// `"on"` cannot be dropped — `"on <date>"` is the commonest alert tail —
  /// but it also cannot be unconditional, because "SHOP ON WHEELS" is a real
  /// name. It ends the payee only when a date plausibly follows.
  static const Set<String> _contextualStopTokens = {'on', 'dt'};

  /// Characters that end a payee outright. ":" earns its place: it is never
  /// inside a merchant name and it closes "Info:", "Queries:" and "Bal:" in
  /// one stroke, which is why several risky word-tokens could be removed.
  static const Set<String> _payeeTerminators = {
    '.', ',', '|', ';', ':', '(', ')', '!', '?', '*', '#',
  };

  /// Extracts the payee from the clause that follows the amount.
  ///
  /// Anchoring at `start` (where the amount ended) is deliberate: the amount
  /// is mandatory and sits inside the transaction clause by definition, so a
  /// leading disclaimer such as "write to us at ..." — or a direction word
  /// like "sent" appearing in a preamble — cannot hijack the lead-in search.
  /// There is intentionally NO whole-message fallback — an alert that phrases
  /// the payee before the amount is declined instead. Declining costs one
  /// uncaptured alert; guessing costs a wrong rule.
  static String? _payee(
      String text, String lower, Direction direction, int start) {
    final leadIns = direction == Direction.credit ? _creditLeadIns : _debitLeadIns;
    for (final leadIn in leadIns) {
      final idx = lower.indexOf(leadIn, start);
      if (idx == -1) continue;
      final tailStart = idx + leadIn.length;
      final cleaned = _trimToPayee(text.substring(tailStart));
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  static bool _isWhitespaceChar(String ch) => RegExp(r'\s').hasMatch(ch);
  static bool _isDigitChar(String ch) => RegExp(r'[0-9]').hasMatch(ch);

  /// Cuts the tail at the first terminator character, then at the first stop
  /// token. Tokenising before comparing is the whole point: a stop token only
  /// ends a payee when it stands alone as a word.
  static String? _trimToPayee(String tail) {
    final words = <String>[];
    final current = StringBuffer();
    for (final ch in tail.split('')) {
      if (_payeeTerminators.contains(ch)) break;
      if (_isWhitespaceChar(ch)) {
        if (current.isNotEmpty) {
          words.add(current.toString());
          current.clear();
        }
        continue;
      }
      current.write(ch);
    }
    if (current.isNotEmpty) words.add(current.toString());

    final kept = <String>[];
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final token = word.toLowerCase();
      if (_payeeStopTokens.contains(token)) break;
      if (_contextualStopTokens.contains(token)) {
        final next = index + 1 < words.length ? words[index + 1] : '';
        if (next.isNotEmpty && _isDigitChar(next[0])) break;
      }
      kept.add(word);
    }
    return kept.isEmpty ? null : kept.join(' ');
  }

  static String? _accountTail(String lower) {
    final regex =
        RegExp(r'(?:a/c|acct|account|ac)\s*(?:no\.?)?\s*[x*]*([0-9]{3,4})');
    return regex.firstMatch(lower)?.group(1);
  }

  static const Map<String, int> _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// `22-09-26`, `22/09/2026`, `22Sep26`, `22-Sep-2026`. A two-digit year is
  /// 2000-based: these alerts are never historical.
  static DateTime? _date(String lower) {
    final numeric = RegExp(r'([0-9]{2})[-/]([0-9]{2})[-/]([0-9]{2,4})');
    final numericMatch = numeric.firstMatch(lower);
    if (numericMatch != null) {
      final d = int.tryParse(numericMatch.group(1)!);
      final m = int.tryParse(numericMatch.group(2)!);
      final y = int.tryParse(numericMatch.group(3)!);
      if (d != null && m != null && y != null) {
        final made = _makeDate(day: d, month: m, year: y);
        if (made != null) return made;
      }
    }
    final named = RegExp(r'([0-9]{1,2})[- ]?([a-z]{3})[- ]?([0-9]{2,4})');
    final namedMatch = named.firstMatch(lower);
    if (namedMatch != null) {
      final d = int.tryParse(namedMatch.group(1)!);
      final m = _months[namedMatch.group(2)!];
      final y = int.tryParse(namedMatch.group(3)!);
      if (d != null && m != null && y != null) {
        final made = _makeDate(day: d, month: m, year: y);
        if (made != null) return made;
      }
    }
    return null;
  }

  static DateTime? _makeDate({required int day, required int month, required int year}) {
    if (day < 1 || day > 31) return null;
    if (month < 1 || month > 12) return null;
    final y = year < 100 ? 2000 + year : year;
    // IST wall-clock (y, month, day) at noon, expressed as the UTC instant
    // that istClock() will read back as that same wall-clock date.
    return DateTime.utc(y, month, day, 12).subtract(istOffset);
  }
}
