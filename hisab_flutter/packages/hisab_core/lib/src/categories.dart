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
  /// mirrors Categorizer.seedRules in Swift.
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

  /// First match wins; patterns are lowercase substrings.
  static String category(String text, List<CategoryRule> rules) {
    final haystack = text.toLowerCase();
    for (final rule in rules) {
      if (haystack.contains(rule.pattern.toLowerCase())) return rule.category;
    }
    return uncategorized;
  }
}
