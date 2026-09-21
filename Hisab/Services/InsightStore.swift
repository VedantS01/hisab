import Foundation
import HisabCore

/// What the user has dismissed or muted on the insight strip. Device
/// preference, not financial data — UserDefaults, same tier as the
/// suggestion prompt's schedule.
enum InsightStore {
    static let dismissedKey = "insights.dismissed"
    static let mutedMerchantsKey = "insights.mutedMerchants"
    static let mutedCategoriesKey = "insights.mutedCategories"

    private static func set(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    private static func insert(_ value: String, into key: String) {
        var current = UserDefaults.standard.stringArray(forKey: key) ?? []
        if !current.contains(value) { current.append(value) }
        UserDefaults.standard.set(current, forKey: key)
    }

    static var suppressions: Suppressions {
        Suppressions(dismissedIDs: set(dismissedKey),
                     mutedMerchants: set(mutedMerchantsKey),
                     mutedCategories: set(mutedCategoriesKey))
    }

    static func dismiss(_ id: String) {
        insert(id, into: dismissedKey)
    }

    static func mute(_ target: MuteTarget) {
        switch target {
        case .merchant(let key): insert(key, into: mutedMerchantsKey)
        case .category(let name): insert(name, into: mutedCategoriesKey)
        }
    }

    /// Drops dismissals for insights that no longer generate, so the stored
    /// set can't grow without bound as months roll by.
    static func prune(keeping live: Set<String>) {
        let stored = set(dismissedKey)
        let kept = stored.intersection(live)
        guard kept.count != stored.count else { return }
        UserDefaults.standard.set(Array(kept).sorted(), forKey: dismissedKey)
    }

    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
        UserDefaults.standard.removeObject(forKey: mutedMerchantsKey)
        UserDefaults.standard.removeObject(forKey: mutedCategoriesKey)
    }
}
