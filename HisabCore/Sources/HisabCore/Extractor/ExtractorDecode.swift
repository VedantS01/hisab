import Foundation

/// Port of `ml/src/hisab_ml/predict.py` `decode`: BIO tags to character spans,
/// best span per label, then the strict normalizers and the admission rule.
///
/// Arithmetic is float64 in numpy's order (`softmax` sums with numpy's
/// pairwise summation, `np.mean` is that sum over n) so ties and near-ties
/// resolve as they do in the reference.
enum ExtractorDecode {
    struct Span: Equatable {
        var label: String
        var start: Int
        var end: Int
        /// Mean token confidence.
        var p: Double
    }

    /// numpy's `pairwise_sum` (what `np.add.reduce` does on a contiguous axis).
    static func pairwiseSum(_ a: ArraySlice<Double>) -> Double {
        let n = a.count, base = a.startIndex
        if n < 8 {
            var res = -0.0
            for x in a { res += x }
            return res
        }
        if n <= 128 {
            var r = Array(a[base..<base + 8])
            var i = 8
            while i < n - n % 8 {
                for j in 0..<8 { r[j] += a[base + i + j] }
                i += 8
            }
            var res = ((r[0] + r[1]) + (r[2] + r[3])) + ((r[4] + r[5]) + (r[6] + r[7]))
            while i < n {
                res += a[base + i]
                i += 1
            }
            return res
        }
        var n2 = n / 2
        n2 -= n2 % 8
        return pairwiseSum(a[base..<base + n2]) + pairwiseSum(a[(base + n2)...])
    }

    /// `_softmax` over one row.
    static func softmax(_ x: [Double]) -> [Double] {
        let top = x.max()!
        let e = x.map { exp($0 - top) }
        let sum = pairwiseSum(e[...])
        return e.map { $0 / sum }
    }

    /// `argmax`: the FIRST index of the maximum.
    static func argmax(_ x: [Double]) -> Int {
        var k = 0
        for i in x.indices where x[i] > x[k] { k = i }
        return k
    }

    /// `spans_from_tags`: (label, start, end, mean token confidence). An I- tag
    /// that does not continue a span of its own label opens a new one.
    static func spansFromTags(offsets: [ExtractorTokenizer.Offset], tagProbs: [[Double]],
                              tags: [String]) -> [Span] {
        var out: [Span] = []
        var cur: (label: String, start: Int, end: Int, ps: [Double])?

        func close() {
            if let c = cur {
                out.append(Span(label: c.label, start: c.start, end: c.end,
                                p: pairwiseSum(c.ps[...]) / Double(c.ps.count)))
            }
            cur = nil
        }

        for (offset, probs) in zip(offsets, tagProbs) {
            if offset.end <= offset.start {
                close()
                continue
            }
            let k = argmax(probs)
            let tag = tags[k]
            if tag == "O" {
                close()
                continue
            }
            let dash = tag.firstIndex(of: "-")!
            let prefix = tag[..<dash], label = String(tag[tag.index(after: dash)...])
            if prefix == "I", let c = cur, c.label == label {
                cur?.end = offset.end
                cur?.ps.append(probs[k])
            } else {
                close()
                cur = (label, offset.start, offset.end, [probs[k]])
            }
        }
        close()
        return out
    }

    /// `clean_edges`: a value is a whole run of digits or letters, never a
    /// slice of one. ASCII classes, as the reference.
    static func cleanEdges(_ text: [Unicode.Scalar], start: Int, end: Int) -> Bool {
        let n = text.count

        func digit(_ c: Unicode.Scalar) -> Bool { (0x30...0x39).contains(c.value) }
        func letter(_ c: Unicode.Scalar) -> Bool {
            (0x61...0x7A).contains(c.value) || (0x41...0x5A).contains(c.value)
        }
        func separator(_ c: Unicode.Scalar) -> Bool { c == "," || c == "." }

        func splitsRun(_ i: Int) -> Bool {
            if i <= 0 || i >= n { return false }
            let a = text[i - 1], b = text[i]
            return (digit(a) && digit(b)) || (letter(a) && letter(b))
        }

        func splitsNumber(_ i: Int) -> Bool {
            // 3,13,938.00 is one number: no edge next to a separator between digits.
            if 2 <= i && i < n && separator(text[i - 1]) && digit(text[i - 2]) && digit(text[i]) {
                return true
            }
            return 1 <= i && i < n - 1 && separator(text[i]) && digit(text[i - 1]) && digit(text[i + 1])
        }

        // A value may START at a letter->digit edge (INR450) but may not END inside a word.
        let endsInsideWord = 0 < end && end < n && (digit(text[end - 1]) || letter(text[end - 1]))
            && (digit(text[end]) || letter(text[end]))
        return !(splitsRun(start) || splitsNumber(start) || splitsNumber(end) || endsInsideWord)
    }

    /// `decode`. `text` is the RAW alert (before `prepare`), as scalars.
    static func decode(text: [Unicode.Scalar], offsets: [ExtractorTokenizer.Offset], tagLogits: [[Double]],
                       seqLogits: [Double], tags: [String], seqClasses: [String]) -> ExtractedAlert {
        let seq = softmax(seqLogits)
        let k = argmax(seq)
        let cls = seqClasses[k]
        let confidence = round4(seq[k])
        if cls == "none" {
            return ExtractedAlert(isTransaction: false, classConfidence: confidence)
        }
        var fields = ExtractedAlert(isTransaction: true, direction: Direction(rawValue: cls),
                                    classConfidence: confidence)
        var best: [String: Span] = [:]
        for span in spansFromTags(offsets: offsets, tagProbs: tagLogits.map(softmax), tags: tags) {
            if !cleanEdges(text, start: span.start, end: span.end) { continue }
            if let held = best[span.label], !(span.p > held.p) { continue }
            best[span.label] = span
        }
        for (label, span) in best {
            let value = slice(text, span.start, span.end)
            switch label {
            case "AMOUNT": fields.amountPaise = ExtractorNormalize.amountPaise(value)
            case "BALANCE": fields.balancePaise = ExtractorNormalize.amountPaise(value)
            case "REF": fields.ref = ExtractorNormalize.ref(value)
            case "OWN_ACCT": fields.ownAccountTail = ExtractorNormalize.acctTail(value)
            case "CPTY_ACCT": fields.counterpartyAccountTail = ExtractorNormalize.acctTail(value)
            case "DATE": fields.dateISO = ExtractorNormalize.dateISO(value)
            case "PAYEE": fields.payee = nonEmpty(ExtractorNormalize.trim(value))
            case "VPA": fields.vpa = nonEmpty(ExtractorNormalize.lower(ExtractorNormalize.trim(value)))
            default: break
            }
        }
        // Admission rule: a movement with no readable amount cannot be booked,
        // so it is not a transaction — whatever the class head says.
        if fields.amountPaise == nil || fields.amountPaise == 0 {
            return ExtractedAlert(isTransaction: false, classConfidence: confidence)
        }
        return fields
    }

    /// Python's `text[s:e]` (clamped, empty when reversed).
    private static func slice(_ text: [Unicode.Scalar], _ start: Int, _ end: Int) -> String {
        let s = min(max(start, 0), text.count), e = min(max(end, s), text.count)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text[s..<e])
        return String(view)
    }

    private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }

    /// Python's `round(x, 4)`: correctly rounded from the exact binary value,
    /// which is what printf's `%.4f` does too.
    private static func round4(_ x: Double) -> Float {
        Float(Double(String(format: "%.4f", x))!)
    }
}
