import Foundation

/// A run of text at a position on a PDF page, in PDF user space (y grows up).
public struct TextFragment: Sendable, Equatable {
    public var text: String
    public var minX: Double
    public var maxX: Double
    public var minY: Double
    public var maxY: Double

    public init(text: String, minX: Double, maxX: Double, minY: Double, maxY: Double) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    var midX: Double { (minX + maxX) / 2 }
    var midY: Double { (minY + maxY) / 2 }
    var height: Double { maxY - minY }
}

/// Rebuilds a bank statement's transaction table from positioned text, for
/// PDFs whose text stream puts every cell on its own line.
///
/// The column header names the columns and fixes their x positions; a parseable
/// date in the leftmost date column starts a row; every other cell joins the
/// row it vertically surrounds. Anything that belongs to no row — the account
/// block, an opening-balance line, page footers — is left out. Nothing here
/// decides what the numbers mean: the result is a plain table for
/// `ColumnInference` (or a model's proposal) and the balance chain to accept
/// or refuse.
public enum StatementLayout {
    public enum Role: Equatable, Sendable {
        case date, narration, reference, debit, credit, amount, balance
    }

    struct Column {
        var label: String
        var role: Role?
        var minX: Double
        var maxX: Double
        var midX: Double { (minX + maxX) / 2 }
    }

    /// Nil when no page has a header naming a date, a balance and an amount
    /// (separate debit and credit columns, or one amount column).
    public static func table(pages: [[TextFragment]]) -> NormalizedTable? {
        var columns: [Column]?
        var rows: [[String]] = []
        var centred = false
        let pages = pages.map { $0.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        // Text printed at the same spot on more than one page: a repeated
        // account block ("To : 31/03/2026"), a footer.
        var pagesWith: [String: Int] = [:]
        for page in pages {
            for key in Set(page.map(spot)) { pagesWith[key, default: 0] += 1 }
        }
        let furniture = Set(pagesWith.filter { $0.value > 1 }.keys)
        for cleaned in pages {
            var body = cleaned
            if let header = findHeader(in: cleaned) {
                columns = header.columns
                body = cleaned.filter { $0.maxY < header.bottom }
            }
            guard let columns else { continue }
            let pageRows = readRows(body, columns: columns, furniture: furniture, centred: &centred)
            // Narration that spilled over the page break belongs to the last
            // row of the previous page.
            if let spill = pageRows.spill, !rows.isEmpty, let narration = columns.firstIndex(where: { $0.role == .narration }) {
                rows[rows.count - 1][narration] = join(rows[rows.count - 1][narration], spill)
            }
            rows += pageRows.rows
        }
        guard let columns, !rows.isEmpty else { return nil }
        return NormalizedTable(rows: [columns.map(\.label)] + rows, container: "pdf")
    }

    // MARK: header

    static func role(of label: String) -> Role? {
        let l = label.lowercased()
        func has(_ pattern: String) -> Bool { l.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\bbalance\b|\bbal\b"#) { return .balance }
        if has(#"withdraw|\bdebit|\bdr\b|paid out"#) { return .debit }
        if has(#"deposit|\bcredit|\bcr\b|paid in"#) { return .credit }
        if has(#"\bdate\b|\bdt\b"#) { return .date }
        if has(#"particular|narration|description|details|remark"#) { return .narration }
        if has(#"cheque|\bchq|\bref|instrument"#) { return .reference }
        if has(#"\bamount\b|\bamt\b"#) { return .amount }
        return nil
    }

    /// Lines of up to three stacked header rows, merged into labelled columns.
    /// The band naming the most roles wins, then the one with the most labelled
    /// columns, then the one with the fewest lines (the topmost on a full tie):
    /// a summary line like "Opening Balance  Total Debit  Total Credit" never
    /// beats the real header, and a period line above it ("From : … To : …")
    /// merges columns away rather than adding any.
    static func findHeader(in fragments: [TextFragment]) -> (columns: [Column], bottom: Double)? {
        let lines = groupLines(fragments)
        var best: (columns: [Column], bottom: Double, score: [Int])?
        for start in lines.indices {
            for count in 1...3 where start + count <= lines.count {
                let band = Array(lines[start..<(start + count)])
                // Stacked header rows sit within ~2.5 line heights.
                guard let top = band.first?.first?.maxY, let bottom = band.last?.first?.minY,
                      top - bottom < 30 else { break }
                let columns = mergeColumns(band.flatMap { $0 })
                let roles = Set(columns.compactMap(\.role))
                let hasAmount = roles.contains(.amount) || (roles.contains(.debit) && roles.contains(.credit))
                let score = [roles.count, columns.filter { $0.role != nil }.count, -count]
                guard roles.contains(.date), roles.contains(.balance), hasAmount else { continue }
                if best.map({ score.lexicographicallyPrecedes($0.score) || score == $0.score }) ?? false { continue }
                best = (columns, band.flatMap { $0 }.map(\.minY).min()! - 0.5, score)
            }
        }
        return best.map { ($0.columns, $0.bottom) }
    }

    /// Fragments that overlap horizontally across stacked header lines are one
    /// label ("Transaction" over "Date", "Cheque" over "No").
    static func mergeColumns(_ fragments: [TextFragment]) -> [Column] {
        var columns: [(minX: Double, maxX: Double, parts: [TextFragment])] = []
        for fragment in fragments.sorted(by: { $0.minX < $1.minX }) {
            if let i = columns.firstIndex(where: { fragment.minX < $0.maxX && fragment.maxX > $0.minX }) {
                columns[i].minX = min(columns[i].minX, fragment.minX)
                columns[i].maxX = max(columns[i].maxX, fragment.maxX)
                columns[i].parts.append(fragment)
            } else {
                columns.append((fragment.minX, fragment.maxX, [fragment]))
            }
        }
        return columns.map { column in
            let label = column.parts.sorted { $0.maxY > $1.maxY }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: " ")
            return Column(label: label, role: role(of: label), minX: column.minX, maxX: column.maxX)
        }
        .sorted { $0.midX < $1.midX }
    }

    /// Fragments on the same baseline (within 2pt), top line first.
    static func groupLines(_ fragments: [TextFragment]) -> [[TextFragment]] {
        var lines: [[TextFragment]] = []
        for fragment in fragments.sorted(by: { $0.midY > $1.midY }) {
            if let last = lines.last?.first, abs(last.midY - fragment.midY) < 2 {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }
        return lines
    }

    // MARK: rows

    /// The nearest header centre — good enough to find the dates, which sit
    /// under their header; not for text, whose header is often centred over
    /// left-aligned cells.
    static func nearestColumn(to x: Double, in columns: [Column]) -> Int {
        var best = 0
        for i in columns.indices where abs(columns[i].midX - x) < abs(columns[best].midX - x) {
            best = i
        }
        return best
    }

    /// Whether a fragment is the kind of value a column of this role holds.
    static func fits(_ fragment: TextFragment, _ role: Role?) -> Bool {
        switch role {
        case .date: return DateShapes.looksLikeDate(fragment.text)
        case .debit, .credit, .amount, .balance: return isNumber(fragment)
        default: return false
        }
    }

    static func isNumber(_ fragment: TextFragment) -> Bool {
        Money.signedPaise(fromDecimalString: fragment.text) != nil
    }

    /// Where each column ends, read off the dated lines. Dates and amounts sit
    /// under their own header, so they mark exactly where a date or amount
    /// column runs; a text column's header is often centred over left-aligned
    /// cells (HDFC's dates end at x 62, its narration starts at 72, its
    /// "Narration" title is centred at 161), so its edge is the whitespace
    /// next to its typed neighbour — or, between two text columns, the widest
    /// strip no text covers. The midpoint of the header centres when text
    /// bridges the gap.
    static func boundaries(columns: [Column], lines: [TextFragment]) -> [Double] {
        var extents = [(minX: Double, maxX: Double)?](repeating: nil, count: columns.count)
        for fragment in lines {
            let c = nearestColumn(to: fragment.midX, in: columns)
            guard fits(fragment, columns[c].role) else { continue }
            extents[c] = (min(extents[c]?.minX ?? .infinity, fragment.minX), max(extents[c]?.maxX ?? -.infinity, fragment.maxX))
        }
        var covered: [(from: Double, to: Double)] = []
        for fragment in lines.sorted(by: { $0.minX < $1.minX }) {
            if let last = covered.last, fragment.minX <= last.to {
                covered[covered.count - 1].to = max(last.to, fragment.maxX)
            } else {
                covered.append((fragment.minX, fragment.maxX))
            }
        }
        func gaps(from a: Double, to b: Double) -> [(from: Double, to: Double)] {
            guard a < b else { return [] }
            var result: [(from: Double, to: Double)] = []
            var x = a
            for span in covered where span.to > x && span.from < b {
                if span.from > x { result.append((x, span.from)) }
                x = max(x, span.to)
            }
            if x < b { result.append((x, b)) }
            return result
        }
        func mid(_ gap: (from: Double, to: Double)?) -> Double? { gap.map { ($0.from + $0.to) / 2 } }

        return columns.indices.dropLast().map { i in
            let left = columns[i], right = columns[i + 1]
            let fallback = (left.midX + right.midX) / 2
            switch (extents[i], extents[i + 1]) {
            case let (l?, r?):
                return l.maxX < r.minX ? (l.maxX + r.minX) / 2 : fallback
            case let (l?, nil):
                return mid(gaps(from: l.maxX, to: right.midX).first) ?? l.maxX
            case let (nil, r?):
                return mid(gaps(from: left.midX, to: r.minX).last) ?? r.minX
            case (nil, nil):
                return mid(gaps(from: left.midX, to: right.midX).max { $0.to - $0.from < $1.to - $1.from }) ?? fallback
            }
        }
    }

    /// `centred` carries across pages: once a row's narration is seen starting
    /// above its date, text above a page's first date is that row's too.
    static func readRows(_ fragments: [TextFragment], columns: [Column], furniture: Set<String> = [],
                         centred: inout Bool) -> (rows: [[String]], spill: String?) {
        guard let dateColumn = columns.firstIndex(where: { $0.role == .date }) else { return ([], nil) }

        // A row starts at every date in the leftmost date column.
        let anchors = fragments.filter { DateShapes.looksLikeDate($0.text) && nearestColumn(to: $0.midX, in: columns) == dateColumn }
            .sorted { $0.midY > $1.midY }
        guard !anchors.isEmpty else { return ([], nil) }
        let lineHeight = median(fragments.map(\.height)) ?? 10

        let dated = fragments.filter { fragment in anchors.contains { abs($0.midY - fragment.midY) < lineHeight / 2 } }
        let edges = boundaries(columns: columns, lines: dated)
        var byColumn = [[TextFragment]](repeating: [], count: columns.count)
        for fragment in fragments {
            // Numbers and dates are placed by their middle (amounts are
            // right-aligned), text by where it starts (it is left-aligned).
            let x = isNumber(fragment) || DateShapes.looksLikeDate(fragment.text) ? fragment.midX : fragment.minX + 1
            byColumn[edges.firstIndex { x < $0 } ?? edges.count].append(fragment)
        }

        // Rows are separated by every date and by every amount on no date's
        // line (an opening balance, a carried-forward total), which closes the
        // row above without starting one.
        let numeric = columns.indices.filter { [.debit, .credit, .amount, .balance].contains(columns[$0].role) }
        var separators: [(y: Double, row: Int?)] = anchors.enumerated().map { ($1.midY, $0) }
        for fragment in numeric.flatMap({ byColumn[$0] }) where isNumber(fragment)
            && !anchors.contains(where: { $0.minY < fragment.maxY && fragment.minY < $0.maxY })
            && !separators.contains(where: { abs($0.y - fragment.midY) < 2 }) {
            separators.append((fragment.midY, nil))
        }
        separators.sort { $0.y > $1.y }

        // Each row's vertical extent: its date, widened by its narration lines.
        var spans = anchors.map { (top: $0.maxY, bottom: $0.minY) }
        var spill: [TextFragment] = []
        if let narrationColumn = columns.firstIndex(where: { $0.role == .narration }) {
            let lines = groupLines(byColumn[narrationColumn])
            let ys = lines.map { line in line.map(\.midY).reduce(0, +) / Double(line.count) }
            let pitch = median(zip(ys, ys.dropFirst()).map { $0 - $1 }) ?? lineHeight * 1.5
            var owner = [Int?](repeating: nil, count: lines.count)  // index into separators
            var above: [Int] = [], below: [Int] = []
            for (i, y) in ys.enumerated() {
                if let s = separators.firstIndex(where: { abs($0.y - y) < 2 }) {
                    owner[i] = s
                } else if let lower = separators.firstIndex(where: { $0.y < y }) {
                    if lower == 0 { above.append(i) }
                } else {
                    below.append(i)
                }
            }
            // Lines between two separators split at the widest gap: IDFC
            // centres a multi-line narration on its date, so its first lines
            // sit above it; HDFC hangs it below at the same pitch as the rows
            // themselves, so a tie goes to the lowest gap.
            for s in separators.indices.dropFirst() {
                let between = ys.indices.filter { owner[$0] == nil && ys[$0] < separators[s - 1].y && ys[$0] > separators[s].y }
                let points = [separators[s - 1].y] + between.map { ys[$0] } + [separators[s].y]
                var split = 0, widest = -Double.infinity
                for g in 0..<(points.count - 1) where points[g] - points[g + 1] >= widest - 0.5 {
                    split = g
                    widest = max(widest, points[g] - points[g + 1])
                }
                for (k, i) in between.enumerated() {
                    owner[i] = k < split ? s - 1 : s
                    if k >= split, separators[s].row != nil { centred = true }
                }
            }
            // Past the first and last separators, only lines that keep the
            // pitch belong to the table, up to the first piece of page
            // furniture; the account block and footers don't.
            func keepsOn(_ i: Int, from y: Double) -> Bool {
                abs(y - ys[i]) <= pitch * 2 && !lines[i].contains { furniture.contains(spot($0)) }
            }
            var y = separators.last!.y
            for i in below {
                guard keepsOn(i, from: y) else { break }
                owner[i] = separators.count - 1
                y = ys[i]
            }
            // Hanging narration above the first date is the previous page's
            // row running on. Centred narration is this row's, up to a gap
            // wider than the line pitch — the padding between two rows —
            // and the previous page's row again above that.
            y = separators[0].y
            var spilling = !centred
            for i in above.reversed() {
                guard keepsOn(i, from: y) else { break }
                if ys[i] - y > pitch * 1.25 { spilling = true }
                if spilling { spill += lines[i] } else { owner[i] = 0 }
                y = ys[i]
            }
            for (i, line) in lines.enumerated() {
                guard let s = owner[i], let row = separators[s].row else { continue }
                spans[row].top = max(spans[row].top, line.map(\.maxY).max()!)
                spans[row].bottom = min(spans[row].bottom, line.map(\.minY).min()!)
            }
        }

        var rows = [[String]](repeating: [String](repeating: "", count: columns.count), count: anchors.count)
        for (c, columnFragments) in byColumn.enumerated() {
            for row in anchors.indices {
                let inRow = columnFragments.filter { $0.midY <= spans[row].top + 1 && $0.midY >= spans[row].bottom - 1 }
                rows[row][c] = text(of: inRow)
            }
        }
        // Rows can overlap only by a broken layout; a fragment claimed twice
        // would double an amount, so such a page yields nothing rather than a guess.
        for row in spans.indices.dropFirst() where spans[row].top > spans[row - 1].bottom + 1 {
            return ([], nil)
        }
        // A date with no amount and no balance beside it is not a transaction
        // (a period line in a repeated account block, say).
        return (rows.filter { row in numeric.contains { !row[$0].isEmpty } }, spill.isEmpty ? nil : text(of: spill))
    }

    static func spot(_ fragment: TextFragment) -> String {
        "\(Int(fragment.minX.rounded())) \(Int(fragment.minY.rounded())) \(fragment.text.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// Top to bottom, left to right, single-spaced.
    static func text(of fragments: [TextFragment]) -> String {
        fragments.sorted { abs($0.midY - $1.midY) > 2 ? $0.midY > $1.midY : $0.minX < $1.minX }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: " ")
    }

    static func join(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : b.isEmpty ? a : a + " " + b
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0 > 0 }.sorted()
        return sorted.isEmpty ? nil : sorted[sorted.count / 2]
    }
}

/// Whether a cell reads as a calendar date in any of the shapes Indian bank
/// statements print. Only a gate for row anchors: `ColumnInference` decides
/// the actual format from the whole column.
enum DateShapes {
    private static let pattern = try! NSRegularExpression(pattern: #"""
        ^(\d{1,2}[-/. ](\d{1,2}|[A-Za-z]{3,9})[-/. ,']*\d{2,4}|\d{4}-\d{2}-\d{2}|[A-Za-z]{3,9} \d{1,2},? \d{4})$
        """#)

    static func looksLikeDate(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return pattern.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
}
