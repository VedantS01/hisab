/// Categorization rules and the bundled ruleset. Port of Categories.swift.
library;

import 'dart:convert';

class CategoryRule {
  final String id;
  final String pattern;
  final String category;
  const CategoryRule(
      {required this.id, required this.pattern, required this.category});
}

class SeedRule {
  final String pattern;
  final String category;
  const SeedRule(this.pattern, this.category);
}

/// A versioned, bundled set of seed rules (rulesets/india-default.json).
class Ruleset {
  final int version;
  final List<SeedRule> rules;
  const Ruleset({required this.version, required this.rules});

  factory Ruleset.fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return Ruleset(
      version: map['version'] as int,
      rules: (map['rules'] as List)
          .map((r) => SeedRule(r['pattern'] as String, r['category'] as String))
          .toList(),
    );
  }
}

class Categorizer {
  static const uncategorized = 'Uncategorized';

  /// Bank-statement spending with no payment-app counterpart.
  static const miscellaneous = 'Miscellaneous';

  /// Movements between the user's own bank accounts — excluded from analytics.
  static const selfTransfer = 'Self Transfer';

  /// Compiled fallback if the bundled ruleset asset is ever missing —
  /// mirrors Categorizer.seedRules in Swift. Order is *not* load-bearing:
  /// [CategoryMatcher] picks the longest matching pattern, and list order only
  /// breaks ties between patterns of equal length.
  static const seedRules = [
    SeedRule('swiggy', 'Food Delivery'), SeedRule('zomato', 'Food Delivery'),
    SeedRule('bigbasket', 'Groceries'), SeedRule('blinkit', 'Groceries'),
    SeedRule('zepto', 'Groceries'), SeedRule('irctc', 'Transport'),
    SeedRule('uber', 'Transport'), SeedRule('ola', 'Transport'),
    SeedRule('rapido', 'Transport'), SeedRule('jio', 'Recharges & Bills'),
    SeedRule('airtel', 'Recharges & Bills'), SeedRule('netflix', 'Subscriptions'),
    SeedRule('spotify', 'Subscriptions'), SeedRule('hotstar', 'Subscriptions'),
    SeedRule('amazon', 'Shopping'), SeedRule('flipkart', 'Shopping'),
    SeedRule('myntra', 'Shopping'), SeedRule('apollo', 'Health'),
    SeedRule('pharmeasy', 'Health'), SeedRule('hpcl', 'Fuel'),
    SeedRule('iocl', 'Fuel'), SeedRule('bpcl', 'Fuel'),
    SeedRule('petrol', 'Fuel'),
  ];

  /// Convenience for one-off categorization: builds a throwaway matcher.
  /// For batch work (a projection over every transaction) build one
  /// [CategoryMatcher] and reuse it — building is O(sum of pattern lengths).
  static String category(String text, List<CategoryRule> rules) =>
      CategoryMatcher(rules).category(text);
}

/// Longest-match categorization over a fixed rule list, backed by an
/// Aho–Corasick automaton built once and matched many times.
///
/// Semantics (must stay byte-identical with the Swift original in
/// `HisabCore/Sources/HisabCore/Categories.swift`):
///
/// 1. Text and patterns are lowercased.
/// 2. Empty patterns are ignored entirely — an empty pattern matches at every
///    position and would otherwise swallow every text.
/// 3. Every pattern occurring anywhere in the text is found (plain substring,
///    not word-bounded: Indian narrations concatenate, e.g. `UPI-ZOMATOLTD`).
/// 4. The **longest** matching pattern wins, so `ajio` beats `jio` whatever the
///    list order.
/// 5. Equal lengths tie-break on the **lowest rule index** (earlier in the
///    supplied list), preserving author intent and keeping this deterministic.
/// 6. No match → [Categorizer.uncategorized].
///
/// ## String units
///
/// The automaton is indexed on **UTF-16 code units** in both languages
/// (`String.codeUnitAt` here, `String.utf16` in Swift) and "longest" is measured
/// in those units. Swift `Character`s (grapheme clusters) and Dart's native code
/// units disagree on non-ASCII input, so neither side's default unit is usable;
/// UTF-16 is the one representation both languages define identically, and
/// UTF-16 is self-synchronising, so substring matching over code units is
/// exactly substring matching over scalars for well-formed strings.
///
/// The indexing unit is therefore not the limit; **lowercasing** is. We swept
/// all 1,112,064 code points through Dart's `String.toLowerCase()` and
/// `Swift.String.lowercased()` and compared: they agree on all but 466, and not
/// one of the 466 is ASCII or Latin-1. So the bundled ruleset, every Indian
/// bank narration, and accented-Latin user rules are all safe. Of the 466, 465
/// are code points Dart does not lowercase at all while Swift does (Cherokee,
/// Adlam, Deseret, Warang Citi, Medefaidrin, Vithkuqi, Old Hungarian, Garay,
/// and a few recent Cyrillic/Greek additions); the last is U+0130 LATIN CAPITAL
/// LETTER I WITH DOT ABOVE, where Swift applies the length-changing
/// SpecialCasing mapping (`i` + U+0307) and Dart the simple one (`i`). U+0130
/// is the worst of the 466 because the mapping changes *length*: a pattern
/// containing it measures one code unit shorter here than in Swift, so the
/// cores can rank two candidate patterns differently, not merely match or miss.
/// A randomized differential run of 3,000 rule-list/text pairs over an alphabet
/// seeded with `é स 上 🍕 İ` found 14 disagreements and every one of them
/// contained U+0130. Closing this would mean shipping our own case table in
/// both languages, which is not worth it until a user rule needs one of those
/// scripts. The limit predates Aho–Corasick — the old `contains` loop
/// lowercased exactly the same way.
///
/// What this also does not do: Unicode normalization. A pattern written with a
/// precomposed `é` (U+00E9) will not match text using `e` + U+0301, in either
/// core — they are different code-unit sequences. Both cores are wrong the same
/// way, which is what parity requires; normalizing is out of scope until a user
/// rule actually needs it.
class CategoryMatcher {
  // Goto trie as parallel arrays — node 0 is the root. Mirrored field for
  // field from Swift so the two read as ports of one another.
  final List<Map<int, int>> _children;
  final List<int> _fail;

  /// Length (in UTF-16 code units) of the pattern ending at each node, or 0.
  final List<int> _termLength;

  /// Index into the supplied rule list of the pattern ending there, or -1.
  final List<int> _termRule;

  /// Nearest proper suffix node that is itself terminal, or -1. Chasing this
  /// chain reports every pattern ending at the current position, not just the
  /// longest — a shorter pattern can be the only match at a position.
  final List<int> _outLink;
  final List<String> _categories;

  factory CategoryMatcher(List<CategoryRule> rules) {
    final children = <Map<int, int>>[<int, int>{}];
    final termLength = <int>[0];
    final termRule = <int>[-1];

    for (var index = 0; index < rules.length; index++) {
      final pattern = rules[index].pattern.toLowerCase();
      if (pattern.isEmpty) continue;
      var node = 0;
      for (var i = 0; i < pattern.length; i++) {
        final unit = pattern.codeUnitAt(i);
        final next = children[node][unit];
        if (next != null) {
          node = next;
        } else {
          children.add(<int, int>{});
          termLength.add(0);
          termRule.add(-1);
          final created = children.length - 1;
          children[node][unit] = created;
          node = created;
        }
      }
      // First rule to claim a node wins: a duplicate pattern later in the list
      // has the same length, so the lowest index takes it.
      if (termRule[node] < 0) {
        termRule[node] = index;
        termLength[node] = pattern.length;
      }
    }

    final fail = List<int>.filled(children.length, 0);
    final outLink = List<int>.filled(children.length, -1);
    final queue = <int>[];
    var head = 0;
    for (final child in children[0].values) {
      fail[child] = 0;
      queue.add(child);
    }
    while (head < queue.length) {
      final node = queue[head];
      head += 1;
      outLink[node] =
          termRule[fail[node]] >= 0 ? fail[node] : outLink[fail[node]];
      children[node].forEach((unit, child) {
        var state = fail[node];
        while (state != 0 && children[state][unit] == null) {
          state = fail[state];
        }
        fail[child] = children[state][unit] ?? 0;
        queue.add(child);
      });
    }

    return CategoryMatcher._(children, fail, termLength, termRule, outLink,
        [for (final rule in rules) rule.category]);
  }

  CategoryMatcher._(this._children, this._fail, this._termLength,
      this._termRule, this._outLink, this._categories);

  /// The category of the longest pattern occurring in [text], ties going to
  /// the lowest rule index; [Categorizer.uncategorized] when nothing matches.
  String category(String text) {
    if (_categories.isEmpty || _children.length == 1) {
      return Categorizer.uncategorized;
    }
    var bestLength = 0;
    var bestRule = -1;
    var state = 0;
    final haystack = text.toLowerCase();
    for (var i = 0; i < haystack.length; i++) {
      final unit = haystack.codeUnitAt(i);
      while (state != 0 && _children[state][unit] == null) {
        state = _fail[state];
      }
      state = _children[state][unit] ?? 0;
      // Outputs along the link chain get strictly shorter, so once one is
      // shorter than the best so far nothing further can improve on it.
      var node = _termRule[state] >= 0 ? state : _outLink[state];
      while (node >= 0) {
        final length = _termLength[node];
        if (length < bestLength) break;
        if (length > bestLength || _termRule[node] < bestRule) {
          bestLength = length;
          bestRule = _termRule[node];
        }
        node = _outLink[node];
      }
    }
    return bestRule >= 0 ? _categories[bestRule] : Categorizer.uncategorized;
  }
}
