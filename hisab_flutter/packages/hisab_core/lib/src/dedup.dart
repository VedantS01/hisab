/// Dedup. Port of Dedup.swift.
library;

import 'content_hash.dart';
import 'domain.dart';

class Dedup {
  /// Indices of `incoming` that are NEW: content hash not already stored and
  /// not seen earlier within the batch (first occurrence wins).
  static List<int> newIndices({
    required List<ParsedTransaction> incoming,
    required Source source,
    required Set<String> existingHashes,
  }) {
    final seen = Set<String>.from(existingHashes);
    final result = <int>[];
    for (var index = 0; index < incoming.length; index++) {
      if (seen.add(incoming[index].contentHash(source))) {
        result.add(index);
      }
    }
    return result;
  }
}
