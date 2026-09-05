import Foundation

public enum Dedup {
    /// Indices of `incoming` that are NEW: content hash not already stored and not seen
    /// earlier within the batch (first occurrence wins).
    public static func newIndices(incoming: [ParsedTransaction], source: Source,
                                  existingHashes: Set<String>) -> [Int] {
        var seen = existingHashes
        var result: [Int] = []
        for (index, txn) in incoming.enumerated() {
            let hash = txn.contentHash(source: source)
            if seen.insert(hash).inserted {
                result.append(index)
            }
        }
        return result
    }
}
