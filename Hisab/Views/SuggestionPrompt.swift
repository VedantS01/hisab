import SwiftUI
import SwiftData
import HisabCore

/// The one-per-day rule suggestion: shown at most once per app launch and per
/// IST calendar day. Accept creates an ordinary editable rule; dismiss mutes
/// the merchant forever; closing the sheet just snoozes until tomorrow.
struct SuggestionPrompt: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredCategoryRule.sortOrder) private var ruleRows: [StoredCategoryRule]

    let suggestion: RuleSuggestion
    @State private var category = ""

    private var existingCategories: [String] {
        Array(Set(ruleRows.map(\.category))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(HisabTheme.sona)
                Text("You've spent \(Money.formatPaise(suggestion.totalPaise)) on \(suggestion.displayMerchant) across \(suggestion.count) payments.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Categorize these?")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    TextField("Category", text: $category)
                        .textFieldStyle(.roundedBorder)
                    Menu {
                        ForEach(existingCategories, id: \.self) { existing in
                            Button(existing) { category = existing }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
                Button("Save rule") {
                    saveRule()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(HisabTheme.khataRed)
                .disabled(category.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Don't ask about this") {
                    SuggestionSchedule.mute(suggestion.merchantPattern)
                    dismiss()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }

    private func saveRule() {
        let order = (ruleRows.map(\.sortOrder).max() ?? -1) + 1
        context.insert(StoredCategoryRule(pattern: suggestion.merchantPattern,
                                          category: category.trimmingCharacters(in: .whitespaces),
                                          sortOrder: order))
        try? context.save()
    }
}

/// UserDefaults bookkeeping for the prompt cadence (≤1 per IST day) and the
/// permanently muted merchants.
enum SuggestionSchedule {
    static let lastShownKey = "suggestion.lastShown"
    static let mutedKey = "suggestion.muted"

    static var todayKey: String {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static var alreadyShownToday: Bool {
        UserDefaults.standard.string(forKey: lastShownKey) == todayKey
    }

    static func markShown() {
        UserDefaults.standard.set(todayKey, forKey: lastShownKey)
    }

    static var muted: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? [])
    }

    static func mute(_ merchantPattern: String) {
        var current = UserDefaults.standard.stringArray(forKey: mutedKey) ?? []
        if !current.contains(merchantPattern) { current.append(merchantPattern) }
        UserDefaults.standard.set(current, forKey: mutedKey)
    }

    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: lastShownKey)
        UserDefaults.standard.removeObject(forKey: mutedKey)
    }
}
