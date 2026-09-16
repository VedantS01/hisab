/// Content-hash identity. Port of ContentHash.swift — the canonical strings
/// MUST stay byte-identical to Swift's; the pin test enforces the shared
/// ground-truth digests across both platforms.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'domain.dart';
import 'year_month.dart';

extension ContentHash on ParsedTransaction {
  /// Stable identity used for cross-document dedup. Within a source, a
  /// transaction reference ID (UPI/bank ref) IS the identity; direction stays
  /// in the key (a refund reuses its payment's reference with the opposite
  /// direction). Rows without a reference fall back to IST day + amount +
  /// direction + normalized narration.
  String contentHash(Source source) {
    final ref = reference;
    final String canonical;
    if (ref != null && ref.isNotEmpty) {
      canonical = '${source.rawValue}|ref|$ref|${direction.name}';
    } else {
      final day = istDayString(date);
      canonical =
          '${source.rawValue}|$day|$amountPaise|${direction.name}|${_normalized(narration)}';
    }
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String _normalized(String text) => text
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .join(' ');
}
