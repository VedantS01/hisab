import Foundation

public struct CategoryRule: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var pattern: String
    public var category: String

    public init(id: UUID = UUID(), pattern: String, category: String) {
        self.id = id
        self.pattern = pattern
        self.category = category
    }
}

/// A versioned, bundled set of seed rules (rulesets/india-default.json).
public struct Ruleset: Codable, Sendable {
    public struct SeedRule: Codable, Sendable {
        public var pattern: String
        public var category: String
        public init(pattern: String, category: String) {
            self.pattern = pattern
            self.category = category
        }
    }

    public var version: Int
    public var rules: [SeedRule]

    public init(version: Int, rules: [SeedRule]) {
        self.version = version
        self.rules = rules
    }
}

public enum Categorizer {
    public static let uncategorized = "Uncategorized"
    /// Bank-statement spending with no payment-app counterpart.
    public static let miscellaneous = "Miscellaneous"
    /// Movements between the user's own bank accounts — excluded from analytics.
    public static let selfTransfer = "Self Transfer"

    /// Defaults tuned for Indian merchants. Order is *not* load-bearing:
    /// `CategoryMatcher` picks the longest matching pattern, and list order only
    /// breaks ties between patterns of equal length.
    public static let seedRules: [CategoryRule] = [
        CategoryRule(pattern: "swiggy", category: "Food Delivery"),
        CategoryRule(pattern: "zomato", category: "Food Delivery"),
        CategoryRule(pattern: "bigbasket", category: "Groceries"),
        CategoryRule(pattern: "blinkit", category: "Groceries"),
        CategoryRule(pattern: "zepto", category: "Groceries"),
        CategoryRule(pattern: "irctc", category: "Transport"),
        CategoryRule(pattern: "uber", category: "Transport"),
        CategoryRule(pattern: "ola", category: "Transport"),
        CategoryRule(pattern: "rapido", category: "Transport"),
        CategoryRule(pattern: "jio", category: "Recharges & Bills"),
        CategoryRule(pattern: "airtel", category: "Recharges & Bills"),
        CategoryRule(pattern: "netflix", category: "Subscriptions"),
        CategoryRule(pattern: "spotify", category: "Subscriptions"),
        CategoryRule(pattern: "hotstar", category: "Subscriptions"),
        CategoryRule(pattern: "amazon", category: "Shopping"),
        CategoryRule(pattern: "flipkart", category: "Shopping"),
        CategoryRule(pattern: "myntra", category: "Shopping"),
        CategoryRule(pattern: "apollo", category: "Health"),
        CategoryRule(pattern: "pharmeasy", category: "Health"),
        CategoryRule(pattern: "hpcl", category: "Fuel"),
        CategoryRule(pattern: "iocl", category: "Fuel"),
        CategoryRule(pattern: "bpcl", category: "Fuel"),
        CategoryRule(pattern: "petrol", category: "Fuel"),
    ]

    /// The bundled india-default ruleset; falls back to the compiled seeds if
    /// the resource is ever missing. User rules always take precedence at the
    /// seeding layer — this only supplies defaults.
    public static func defaultRuleset() -> Ruleset {
        if let url = Bundle.module.url(forResource: "india-default", withExtension: "json",
                                       subdirectory: "Resources/rulesets"),
           let data = try? Data(contentsOf: url),
           let ruleset = try? JSONDecoder().decode(Ruleset.self, from: data) {
            return ruleset
        }
        return Ruleset(version: 0, rules: seedRules.map {
            Ruleset.SeedRule(pattern: $0.pattern, category: $0.category)
        })
    }

    /// Convenience for one-off categorization: builds a throwaway matcher.
    /// For batch work (a projection over every transaction) build one
    /// `CategoryMatcher` and reuse it — building is O(sum of pattern lengths).
    public static func category(for text: String, rules: [CategoryRule]) -> String {
        CategoryMatcher(rules: rules).category(for: text)
    }
}

/// Longest-match categorization over a fixed rule list, backed by an
/// Aho–Corasick automaton built once and matched many times.
///
/// Semantics (must stay byte-identical with the Dart port in
/// `hisab_flutter/packages/hisab_core/lib/src/categories.dart`):
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
/// 6. No match → `Categorizer.uncategorized`.
///
/// ## String units
///
/// The automaton is indexed on **UTF-16 code units** in both languages
/// (`String.utf16` here, `String.codeUnitAt` in Dart) and "longest" is measured
/// in those units. Swift `Character`s (grapheme clusters) and Dart's native code
/// units disagree on non-ASCII input, so neither side's default unit is usable;
/// UTF-16 is the one representation both languages define identically, and
/// UTF-16 is self-synchronising, so substring matching over code units is
/// exactly substring matching over scalars for well-formed strings.
///
/// The indexing unit is therefore not the limit; **lowercasing** is. We swept
/// all 1,112,064 code points through `Swift.String.lowercased()` and Dart's
/// `String.toLowerCase()` and compared: they agree on all but 466, and not one
/// of the 466 is ASCII or Latin-1. So the bundled ruleset, every Indian bank
/// narration, and accented-Latin user rules are all safe. Of the 466, 465 are
/// code points Dart does not lowercase at all while Swift does (Cherokee,
/// Adlam, Deseret, Warang Citi, Medefaidrin, Vithkuqi, Old Hungarian, Garay,
/// and a few recent Cyrillic/Greek additions); the last is U+0130 LATIN CAPITAL
/// LETTER I WITH DOT ABOVE, where Swift applies the length-changing
/// SpecialCasing mapping (`i` + U+0307) and Dart the simple one (`i`). U+0130
/// is the worst of the 466 because the mapping changes *length*: a pattern
/// containing it measures one code unit longer here than in Dart, so the cores
/// can rank two candidate patterns differently, not merely match or miss. A
/// randomized differential run of 3,000 rule-list/text pairs over an alphabet
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
public struct CategoryMatcher: Sendable {
    // Goto trie as parallel arrays — node 0 is the root. Mirrored field for
    // field in Dart so the two read as ports of one another.
    private let children: [[UInt16: Int]]
    private let fail: [Int]
    /// Length (in UTF-16 code units) of the pattern ending at this node, or 0.
    private let termLength: [Int]
    /// Index into the supplied rule list of the pattern ending here, or -1.
    private let termRule: [Int]
    /// Nearest proper suffix node that is itself terminal, or -1. Chasing this
    /// chain reports every pattern ending at the current position, not just the
    /// longest — a shorter pattern can be the only match at a position.
    private let outLink: [Int]
    private let categories: [String]

    public init(rules: [CategoryRule]) {
        var children: [[UInt16: Int]] = [[:]]
        var termLength: [Int] = [0]
        var termRule: [Int] = [-1]

        for (index, rule) in rules.enumerated() {
            let pattern = Array(rule.pattern.lowercased().utf16)
            if pattern.isEmpty { continue }
            var node = 0
            for unit in pattern {
                if let next = children[node][unit] {
                    node = next
                } else {
                    children.append([:])
                    termLength.append(0)
                    termRule.append(-1)
                    let next = children.count - 1
                    children[node][unit] = next
                    node = next
                }
            }
            // First rule to claim a node wins: a duplicate pattern later in the
            // list has the same length, so the lowest index takes it.
            if termRule[node] < 0 {
                termRule[node] = index
                termLength[node] = pattern.count
            }
        }

        var fail = [Int](repeating: 0, count: children.count)
        var outLink = [Int](repeating: -1, count: children.count)
        var queue: [Int] = []
        var head = 0
        for (_, child) in children[0] {
            fail[child] = 0
            queue.append(child)
        }
        while head < queue.count {
            let node = queue[head]
            head += 1
            outLink[node] = termRule[fail[node]] >= 0 ? fail[node] : outLink[fail[node]]
            for (unit, child) in children[node] {
                var state = fail[node]
                while state != 0 && children[state][unit] == nil { state = fail[state] }
                fail[child] = children[state][unit] ?? 0
                queue.append(child)
            }
        }

        self.children = children
        self.fail = fail
        self.termLength = termLength
        self.termRule = termRule
        self.outLink = outLink
        self.categories = rules.map(\.category)
    }

    /// The category of the longest pattern occurring in `text`, ties going to
    /// the lowest rule index; `Categorizer.uncategorized` when nothing matches.
    public func category(for text: String) -> String {
        if categories.isEmpty || children.count == 1 { return Categorizer.uncategorized }
        var bestLength = 0
        var bestRule = -1
        var state = 0
        for unit in text.lowercased().utf16 {
            while state != 0 && children[state][unit] == nil { state = fail[state] }
            state = children[state][unit] ?? 0
            // Outputs along the link chain get strictly shorter, so once one is
            // shorter than the best so far nothing further can improve on it.
            var node = termRule[state] >= 0 ? state : outLink[state]
            while node >= 0 {
                let length = termLength[node]
                if length < bestLength { break }
                if length > bestLength || termRule[node] < bestRule {
                    bestLength = length
                    bestRule = termRule[node]
                }
                node = outLink[node]
            }
        }
        return bestRule >= 0 ? categories[bestRule] : Categorizer.uncategorized
    }
}
