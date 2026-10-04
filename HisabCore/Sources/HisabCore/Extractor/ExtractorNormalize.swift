import Foundation

/// Port of `ml/src/hisab_ml/normalize.py`: span text -> field value, strict on
/// purpose (a span that does not normalize is absent, never repaired).
///
/// Casing and whitespace are ASCII-only, exactly as the reference: `lower`,
/// `upper` and `trim` below, never `lowercased()` / `.whitespaces`. Regexes
/// spell the reference's `re.A` classes out (`\d` -> `[0-9]`, `[a-z]` under
/// `re.I` -> `[a-zA-Z]`); NSRegularExpression matches code points, as Python
/// does. Python's `$` (end, or before a final "\n") is `(?=\n?\z)`.
enum ExtractorNormalize {
    /// `WS`
    static let ws: Set<UInt32> = [0x20, 0x09, 0x0A, 0x0D, 0x0B, 0x0C]

    static func lower(_ s: String) -> String {
        map(s) { (0x41...0x5A).contains($0.value) ? Unicode.Scalar($0.value + 0x20)! : $0 }
    }

    static func upper(_ s: String) -> String {
        map(s) { (0x61...0x7A).contains($0.value) ? Unicode.Scalar($0.value - 0x20)! : $0 }
    }

    static func trim(_ s: String) -> String { strip(s, ws) }

    // MARK: amount

    private static let amountRE = regex(
        #"\A(?:[0-9]+|[0-9]{1,2}(?:,[0-9]{2})*,[0-9]{3}|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?"# + pyEnd)

    static func amountPaise(_ text: String) -> Int64? {
        var s = Array(trim(text).unicodeScalars)
        if s.count >= 2, s[s.count - 2] == "/", s[s.count - 1] == "-" { s.removeLast(2) }   // removesuffix("/-")
        guard matches(amountRE, string(s)) else { return nil }
        let joined = s.filter { $0 != "," }
        let dot = joined.firstIndex(of: ".")
        let rupees = string(dot.map { joined[..<$0] } ?? joined[...])
        let frac = dot.map { Array(joined[($0 + 1)...]) } ?? []
        guard let r = pyInt(rupees), let f = pyInt(string((frac + ["0", "0"]).prefix(2))) else { return nil }
        let (scaled, o1) = r.multipliedReportingOverflow(by: 100)
        let (sum, o2) = scaled.addingReportingOverflow(f)
        return o1 || o2 ? nil : sum
    }

    // MARK: account tail

    private static let tailRE = regex("([0-9]{3,})" + pyEnd)

    static func acctTail(_ text: String) -> String? {
        // Last 4 at most: one account shows as XX8816, XXXXXXX8816 and XXXXX308816.
        guard let groups = search(tailRE, trim(text)) else { return nil }
        return string(groups[0].unicodeScalars.suffix(4))
    }

    // MARK: reference

    private static let refREs = [
        regex(#"\A[0-9]{12}"# + pyEnd),                                  // UPI RRN / IMPS ref
        regex(#"\A[A-Z]{4}(?:[A-Z0-9]{12}|[A-Z0-9]{18})"# + pyEnd),     // NEFT/RTGS UTR
        regex(#"\A[A-Z](?:[0-9]{15}|[0-9]{21})"# + pyEnd),               // older NEFT UTR
    ]

    static func ref(_ text: String) -> String? {
        let s = upper(trim(text))
        // At least 8 digits: a reference is mostly number, never a word.
        return digits(s) >= 8 && refREs.contains(where: { matches($0, s) }) ? s : nil
    }

    // MARK: date

    private static let months = Dictionary(uniqueKeysWithValues:
        "jan feb mar apr may jun jul aug sep oct nov dec".split(separator: " ").enumerated()
            .map { (String($1), $0 + 1) })
    private static let fullMonths = Dictionary(uniqueKeysWithValues:
        "january february march april may june july august september october november december"
            .split(separator: " ").enumerated().map { (String($1), $0 + 1) })

    private enum Kind { case dmy, dby, dBy, bdy, ymd, dm, db, bd }

    /// `_DATE_PATTERNS`, tried in order, each a full match.
    private static let datePatterns: [(NSRegularExpression, Kind)] = [
        (full(#"([0-9]{1,2})([-/.])([0-9]{1,2})\2([0-9]{2}|[0-9]{4})"#), .dmy),   // 22-09-26, 22/09/2026
        (full(#"([0-9]{1,2})-([a-zA-Z]{3})-([0-9]{2}|[0-9]{4})"#), .dby),         // 22-Sep-26
        (full(#"([0-9]{1,2})([a-zA-Z]{3})([0-9]{2}|[0-9]{4})"#), .dby),           // 22Sep26
        (full(#"([0-9]{1,2}) ([a-zA-Z]{3}) ([0-9]{2}|[0-9]{4})"#), .dby),         // 22 Sep 2026
        (full(#"([0-9]{1,2})([- ])([a-zA-Z]+)\2([0-9]{4})"#), .dBy),              // 22-September-2026
        (full(#"([a-zA-Z]{3}) ([0-9]{1,2}), ([0-9]{4})"#), .bdy),                 // Sep 22, 2026
        (full(#"([0-9]{4})-([0-9]{1,2})-([0-9]{1,2})"#), .ymd),                   // 2026-09-22
    ]
    /// `_YEARLESS_PATTERNS`: HDFC writes "14-08"; the app supplies the year.
    private static let yearlessPatterns: [(NSRegularExpression, Kind)] = [
        (full(#"([0-9]{1,2})-([0-9]{1,2})"#), .dm), (full(#"([0-9]{1,2})/([0-9]{1,2})"#), .dm),
        (full(#"([0-9]{1,2})-([a-zA-Z]{3})"#), .db), (full(#"([0-9]{1,2}) ([a-zA-Z]{3})"#), .db),
        (full(#"([a-zA-Z]{3}) ([0-9]{1,2})"#), .bd), (full(#"([0-9]{1,2})([a-zA-Z]{3})"#), .db),
    ]
    /// `(\d)(?:st|nd|rd|th)\b` under `re.I | re.A`. The character before `\b`
    /// is always a word character, so `\b` is "no ASCII word character next".
    private static let ordinalRE = regex(#"([0-9])(?:[sS][tT]|[nN][dD]|[rR][dD]|[tT][hH])(?![A-Za-z0-9_])"#)

    /// strptime's %y pivot: 69-99 -> 19xx, 00-68 -> 20xx.
    private static func year(_ y: String) -> Int {
        let n = Int(y)!
        return y.unicodeScalars.count == 4 ? n : (n >= 69 ? 1900 + n : 2000 + n)
    }

    /// (year, month, day) from a match, or nil if a month name is unknown.
    /// Yearless kinds use 2000, a leap year, so 29 Feb survives the check.
    private static func ymd(_ kind: Kind, _ g: [String]) -> (Int, Int, Int)? {
        switch kind {
        case .dmy:
            return (year(g[3]), Int(g[2])!, Int(g[0])!)
        case .dby:
            guard let m = months[lower(g[1])] else { return nil }
            return (year(g[2]), m, Int(g[0])!)
        case .dBy:
            guard let m = fullMonths[lower(g[2])] else { return nil }
            return (Int(g[3])!, m, Int(g[0])!)
        case .bdy:
            guard let m = months[lower(g[0])] else { return nil }
            return (Int(g[2])!, m, Int(g[1])!)
        case .ymd:
            return (Int(g[0])!, Int(g[1])!, Int(g[2])!)
        case .dm:
            return (2000, Int(g[1])!, Int(g[0])!)
        case .db:
            guard let m = months[lower(g[1])] else { return nil }
            return (2000, m, Int(g[0])!)
        case .bd:
            guard let m = months[lower(g[0])] else { return nil }
            return (2000, m, Int(g[1])!)
        }
    }

    private static func valid(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard 1 <= m && m <= 12 && d >= 1 else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    }

    /// ISO date, or `--MM-DD` when the alert names no year.
    static func dateISO(_ text: String) -> String? {
        var s = trim(text)
        s = ordinalRE.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                               withTemplate: "$1")                    // 31st -> 31
        s = trim(collapseWS(map(s) { $0 == "'" ? " " : $0 }))                         // Oct' 2024 -> Oct 2024
        for (patterns, yearless) in [(datePatterns, false), (yearlessPatterns, true)] {
            for (rx, kind) in patterns {
                guard let g = search(rx, s), let date = ymd(kind, g), valid(date.0, date.1, date.2) else {
                    continue
                }
                let (y, mo, d) = date
                return yearless ? "--\(pad(mo, 2))-\(pad(d, 2))" : "\(pad(y, 4))-\(pad(mo, 2))-\(pad(d, 2))"
            }
        }
        return nil
    }

    // MARK: name

    private static let honorificRE = regex(#"^(?:mr|mrs|ms|miss|dr|shri|smt|m/s)\.? +"#)

    static func name(_ text: String) -> String? {
        let s = lower(strip(collapseWS(text), [0x20, 0x2E, 0x2C, 0x3A, 0x3B, 0x2D]))   // strip(" .,:;-")
        var scalars = Array(s.unicodeScalars)
        if let m = honorificRE.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
            scalars.removeFirst(m.range.length)   // the match is ASCII: UTF-16 length == scalar count
        }
        return scalars.isEmpty ? nil : string(scalars)
    }

    // MARK: helpers

    private static let pyEnd = #"(?=\n?\z)"#

    static func digits(_ s: String) -> Int {
        s.unicodeScalars.filter { (0x30...0x39).contains($0.value) }.count
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern)
    }

    /// For `re.fullmatch`.
    private static func full(_ pattern: String) -> NSRegularExpression {
        regex(#"\A(?:"# + pattern + #")\z"#)
    }

    private static func matches(_ rx: NSRegularExpression, _ s: String) -> Bool {
        rx.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Groups 1... of the leftmost match.
    private static func search(_ rx: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = rx.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }

    /// `[ \t\n\r\x0b\x0c]+` -> " ".
    private static func collapseWS(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        var inRun = false
        for c in s.unicodeScalars {
            if ws.contains(c.value) {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(c)
                inRun = false
            }
        }
        return String(out)
    }

    /// `str.strip(chars)`.
    private static func strip(_ s: String, _ chars: Set<UInt32>) -> String {
        let u = Array(s.unicodeScalars)
        var a = 0, b = u.count
        while a < b && chars.contains(u[a].value) { a += 1 }
        while b > a && chars.contains(u[b - 1].value) { b -= 1 }
        return string(u[a..<b])
    }

    /// Python `int()` on a digit string the regex already vetted; it may carry
    /// the "\n" that Python's `$` lets through. Overflow is nil (Python is unbounded).
    private static func pyInt(_ s: String) -> Int64? { Int64(trim(s)) }

    private static func map(_ s: String, _ f: (Unicode.Scalar) -> Unicode.Scalar) -> String {
        string(s.unicodeScalars.map(f))
    }

    private static func string<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }
}
