/// Declarative bank-statement layout. Port of FormatSpec.swift. Hard rule:
/// this format never grows an expression language or any eval-like field.
library;

import 'dart:convert';

class FormatSpec {
  final String id;
  final String sourceID;
  final String bankName;
  final bool provisional;
  /// role → case-insensitive regex matched against a header cell.
  /// Roles: date, narration, reference, debit, credit, amount, drcr, balance.
  final Map<String, String> headerPatterns;
  /// Whole-row regexes (cells joined with "|") dropped from the body.
  final List<String> furniturePatterns;
  /// Tried in order; the first that parses every body date wins.
  final List<String> dateFormats;
  /// "debitCredit" | "signedAmount" | "amountDRCR" | "unsignedChain"
  final String signConvention;
  final List<String>? referencePatterns;
  /// Case-insensitive regexes that must each match somewhere in the document
  /// text for the spec to apply (disambiguates identical table shapes).
  final List<String>? detectPatterns;

  const FormatSpec({
    required this.id,
    required this.sourceID,
    required this.bankName,
    this.provisional = false,
    required this.headerPatterns,
    this.furniturePatterns = const [],
    required this.dateFormats,
    required this.signConvention,
    this.referencePatterns,
    this.detectPatterns,
  });

  factory FormatSpec.fromJsonString(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return FormatSpec(
      id: map['id'] as String,
      sourceID: map['sourceID'] as String,
      bankName: map['bankName'] as String,
      provisional: map['provisional'] as bool? ?? false,
      headerPatterns: (map['headerPatterns'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as String)),
      furniturePatterns: (map['furniturePatterns'] as List? ?? [])
          .map((e) => e as String)
          .toList(),
      dateFormats:
          (map['dateFormats'] as List).map((e) => e as String).toList(),
      signConvention: map['signConvention'] as String,
      referencePatterns: (map['referencePatterns'] as List?)
          ?.map((e) => e as String)
          .toList(),
      detectPatterns: (map['detectPatterns'] as List?)
          ?.map((e) => e as String)
          .toList(),
    );
  }
}

class SpecStore {
  /// Parses a set of spec JSON strings (the app supplies asset contents; the
  /// package stays IO-free). Silently drops undecodable entries — CI's
  /// bundled-spec tests catch those upstream.
  static List<FormatSpec> parseAll(Iterable<String> jsonStrings) {
    final specs = <FormatSpec>[];
    for (final json in jsonStrings) {
      try {
        specs.add(FormatSpec.fromJsonString(json));
      } catch (_) {
        continue;
      }
    }
    specs.sort((a, b) => a.id.compareTo(b.id));
    return specs;
  }
}
