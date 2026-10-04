import Foundation

/// Port of `ml/src/hisab_ml/wordpiece.py` (BERT normalizer -> BERT
/// pre-tokenizer -> Digits -> WordPiece, uncased) and `features.prepare`.
///
/// Every index is a Unicode scalar index into the text — Python's code point
/// index — never a `String.Index` or UTF-16 offset. Vocabulary keys are scalar
/// arrays, not `String`s: `String` equality is canonical equivalence, and the
/// reference compares code points.
struct ExtractorTokenizer: Sendable {
    struct Offset: Equatable, Sendable {
        var start: Int
        var end: Int
    }

    struct Encoding: Equatable, Sendable {
        var ids: [Int32]
        /// (0, 0) for [CLS] and [SEP].
        var offsets: [Offset]
    }

    /// `chartable.json`: the Unicode facts the normalizer and pre-tokenizer
    /// need, generated from Python's unicodedata.
    struct Table: Sendable {
        let removed: [ClosedRange<UInt32>]
        let map: [UInt32: [UInt32]]
        let punct: [ClosedRange<UInt32>]
        let numeric: [ClosedRange<UInt32>]

        private struct Raw: Decodable {
            var removed: [[UInt32]]
            var map: [String: String]
            var punct: [[UInt32]]
            var numeric: [[UInt32]]
        }

        init(json: Data) throws {
            let raw = try JSONDecoder().decode(Raw.self, from: json)
            removed = raw.removed.map { $0[0]...$0[1] }
            punct = raw.punct.map { $0[0]...$0[1] }
            numeric = raw.numeric.map { $0[0]...$0[1] }
            var map: [UInt32: [UInt32]] = [:]
            for (key, value) in raw.map {
                guard let cp = UInt32(key) else { throw ExtractorError.badOutput("chartable key \(key)") }
                map[cp] = value.unicodeScalars.map(\.value)
            }
            self.map = map
        }

        static func contains(_ ranges: [ClosedRange<UInt32>], _ cp: UInt32) -> Bool {
            var lo = 0, hi = ranges.count - 1
            while lo <= hi {
                let mid = (lo + hi) / 2
                if cp < ranges[mid].lowerBound {
                    hi = mid - 1
                } else if cp > ranges[mid].upperBound {
                    lo = mid + 1
                } else {
                    return true
                }
            }
            return false
        }

        func isRemoved(_ cp: UInt32) -> Bool { Self.contains(removed, cp) }

        func isPunct(_ cp: UInt32) -> Bool {
            (0x21...0x2F).contains(cp) || (0x3A...0x40).contains(cp) || (0x5B...0x60).contains(cp)
                || (0x7B...0x7E).contains(cp) || Self.contains(punct, cp)
        }

        func isNumeric(_ cp: UInt32) -> Bool { Self.contains(numeric, cp) }
    }

    static let cls = "[CLS]".unicodeScalars.map(\.value)
    static let sep = "[SEP]".unicodeScalars.map(\.value)
    static let unk = "[UNK]".unicodeScalars.map(\.value)
    static let maxWordChars = 100
    /// BERT's CJK blocks: each ideograph becomes its own word.
    static let cjk: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F,
        0x2B820...0x2CEAF, 0xF900...0xFAFF, 0x2F800...0x2FA1F,
    ]
    static let whiteSpace: Set<UInt32> = Set([0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680]
        + Array(0x2000..<0x200B) + [0x2028, 0x2029, 0x202F, 0x205F, 0x3000])
    private static let hashHash: [UInt32] = [0x23, 0x23]

    let vocab: [[UInt32]: Int32]
    let table: Table
    /// `features.prepare`'s same-length character map (₹ -> $, • -> *).
    let charMap: [UInt32: UInt32]

    /// `vocabTxt`: one token per line, id = line index (`load_vocab`).
    init(vocabTxt: Data, table: Table, charMap: [String: String]) {
        var vocab: [[UInt32]: Int32] = [:]
        var line: [UInt32] = []
        var index: Int32 = 0
        for scalar in String(decoding: vocabTxt, as: UTF8.self).unicodeScalars {
            if scalar.value == 0x0A {
                if !line.isEmpty { vocab[line] = index }
                line.removeAll(keepingCapacity: true)
                index += 1
            } else {
                line.append(scalar.value)
            }
        }
        if !line.isEmpty { vocab[line] = index }
        self.vocab = vocab
        self.table = table
        var map: [UInt32: UInt32] = [:]
        for (from, to) in charMap {
            if let f = from.unicodeScalars.first, let t = to.unicodeScalars.first { map[f.value] = t.value }
        }
        self.charMap = map
    }

    /// `features.prepare`.
    func prepare(_ text: [Unicode.Scalar]) -> [UInt32] {
        text.map { charMap[$0.value] ?? $0.value }
    }

    /// `_normalize`: (normalized scalar, index of the original scalar it came from).
    func normalize(_ text: [UInt32]) -> [(UInt32, Int)] {
        var out: [(UInt32, Int)] = []
        out.reserveCapacity(text.count)
        for (i, cp) in text.enumerated() {
            if Self.whiteSpace.contains(cp) {
                out.append((0x20, i))
            } else if table.isRemoved(cp) {
                continue
            } else if Self.cjk.contains(where: { $0.contains(cp) }) {
                out.append(contentsOf: [(UInt32(0x20), i), (cp, i), (UInt32(0x20), i)])
            } else {
                for ch in table.map[cp] ?? [cp] { out.append((ch, i)) }
            }
        }
        return out
    }

    /// `_words`: split on whitespace (dropped), isolate each punctuation
    /// character, then split digit runs from everything else.
    func words(_ norm: [(UInt32, Int)]) -> [[(UInt32, Int)]] {
        var words: [[(UInt32, Int)]] = []
        var cur: [(UInt32, Int)] = []

        func flush() {
            if !cur.isEmpty { words.append(cur) }
            cur = []
        }

        for (ch, i) in norm {
            if ch == 0x20 {
                flush()
            } else if table.isPunct(ch) {
                flush()
                words.append([(ch, i)])
            } else {
                if let last = cur.last, table.isNumeric(last.0) != table.isNumeric(ch) {
                    flush()
                }
                cur.append((ch, i))
            }
        }
        flush()
        return words
    }

    /// `_wordpiece`: (id, start index into word, end index) pieces, or one
    /// [UNK] for the word.
    func wordpiece(_ word: [(UInt32, Int)]) -> [(id: Int32, start: Int, end: Int)] {
        let chars = word.map(\.0)
        let unk = vocab[Self.unk]!
        if chars.count > Self.maxWordChars {
            return [(unk, 0, chars.count)]
        }
        var pieces: [(id: Int32, start: Int, end: Int)] = []
        var start = 0
        while start < chars.count {
            var end = chars.count
            var hit: Int32?
            while start < end {
                let sub = start == 0 ? Array(chars[start..<end]) : Self.hashHash + chars[start..<end]
                if let id = vocab[sub] {
                    hit = id
                    break
                }
                end -= 1
            }
            guard let hit else { return [(unk, 0, chars.count)] }
            pieces.append((hit, start, end))
            start = end
        }
        return pieces
    }

    /// `encode`, on text that has already been through `prepare`.
    func encode(_ text: [UInt32], maxLen: Int) -> Encoding {
        var ids: [Int32] = [vocab[Self.cls]!]
        var offsets = [Offset(start: 0, end: 0)]
        for word in words(normalize(text)) {
            for (pieceID, s, e) in wordpiece(word) {
                if ids.count == maxLen - 1 { break }
                ids.append(pieceID)
                offsets.append(Offset(start: word[s].1, end: word[e - 1].1 + 1))
            }
        }
        ids.append(vocab[Self.sep]!)
        offsets.append(Offset(start: 0, end: 0))
        return Encoding(ids: ids, offsets: offsets)
    }
}
