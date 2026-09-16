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

    /// Defaults tuned for Indian merchants; order matters (first match wins).
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

    public static func category(for text: String, rules: [CategoryRule]) -> String {
        let haystack = text.lowercased()
        for rule in rules where haystack.contains(rule.pattern.lowercased()) {
            return rule.category
        }
        return uncategorized
    }
}
