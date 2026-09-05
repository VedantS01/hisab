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

public enum Categorizer {
    public static let uncategorized = "Uncategorized"

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

    public static func category(for text: String, rules: [CategoryRule]) -> String {
        let haystack = text.lowercased()
        for rule in rules where haystack.contains(rule.pattern.lowercased()) {
            return rule.category
        }
        return uncategorized
    }
}
