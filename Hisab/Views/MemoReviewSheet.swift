import SwiftUI
import SwiftData
import HisabCore

// MARK: - IST rendering

/// Dates in this app are Asia/Kolkata, always.
///
/// P8: a bare `.formatted(...)` renders in the DEVICE timezone, so a phone
/// that has travelled shows a capture on the wrong day — and the capture hash
/// itself is keyed on the IST day, so the two would disagree. Same
/// explicit-formatter shape `SuggestionSchedule` uses; `ISTDay.label` is the
/// repo's day rendering and is reused rather than re-spelled.
enum ISTStamp {
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = YearMonth.istCalendar
        formatter.timeZone = YearMonth.istCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// "22 Sep 2026" — the day only.
    static func day(_ date: Date) -> String { ISTDay.label(date) }

    /// "22 Sep 2026, 4:18 PM IST". The zone is spelled out because the whole
    /// point of the explicit formatter is that this is NOT the device's clock.
    static func dayTime(_ date: Date) -> String {
        "\(ISTDay.label(date)), \(time.string(from: date)) IST"
    }
}

// MARK: - the offer

/// The one place a proposed rule is measured and written.
///
/// Both the review sheet and the queued-offer sheet go through here, so the
/// number the user is shown and the rule that lands come from the same code in
/// both paths — and so the debug harness measures what the buttons do.
@MainActor
enum RuleOffers {
    /// How many recorded transactions the proposed rule would really move.
    ///
    /// `RuleImpact` simulates the matcher on both sides, so this is exact by
    /// construction for the rows it is given; `Queries.impactRows` is where the
    /// row population and the two exclusion flags are decided.
    static func affectedCount(pattern: String, category: String,
                              txns: [StoredTransaction], matches: [StoredMatch],
                              selfTransfers: Set<UUID>, rules: [CategoryRule]) -> Int {
        RuleImpact.affectedCount(
            pattern: pattern, category: category,
            rows: Queries.impactRows(txns, matches: matches, selfTransfers: selfTransfers),
            rules: rules)
    }

    /// Writes the accepted rule, following `SuggestionPrompt.saveRule`: the new
    /// rule takes the highest `sortOrder`.
    ///
    /// That is not cosmetic. `RuleImpact.affectedCount` APPENDS the proposed
    /// rule when it simulates, and `CategoryMatcher` breaks a same-length tie
    /// by lowest rule index — so a rule stored anywhere but the end could lose
    /// or win a tie the count did not predict, and the promise would be wrong
    /// for exactly the rows a tie decides.
    ///
    /// No backfill loop: `Queries.effectiveCategory` derives a category at read
    /// time, so every matching row changes the moment the rule is saved.
    static func createRule(pattern: String, category: String,
                           existing: [StoredCategoryRule], in ctx: ModelContext) {
        let order = (existing.map(\.sortOrder).max() ?? -1) + 1
        ctx.insert(StoredCategoryRule(pattern: pattern, category: category, sortOrder: order))
        try? ctx.save()
    }
}

/// A measured offer, ready to show. `count` is fixed at the moment the
/// category was chosen so the sentence cannot change under the user's finger.
struct MeasuredOffer: Identifiable, Equatable {
    var captureHash: String
    var pattern: String
    var category: String
    var count: Int

    var id: String { "\(captureHash)|\(category)" }
}

// MARK: - the review sheet

/// Sheet wrapper: a `Done` button and its own navigation stack, for the root
/// `.sheet(item:)`. The inbox pushes `MemoReviewContent` instead.
struct MemoReviewSheet: View {
    let captureHash: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MemoReviewContent(captureHash: captureHash)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// One captured alert, and the categorization that turns it into a rule.
///
/// P4: every input is a `@Query`, including the memo itself — which is looked
/// up by hash over ALL memos rather than over the pending ones, because
/// assigning a category is precisely what removes it from the pending set. A
/// category assigned from a notification button therefore updates this view
/// while it is open, instead of leaving it showing the answer it had at
/// presentation time.
struct MemoReviewContent: View {
    let captureHash: String

    @Environment(\.modelContext) private var context
    @Query(sort: \StoredPendingMemo.capturedAt, order: .reverse)
    private var memoRows: [StoredPendingMemo]
    @Query(sort: \StoredTransaction.date, order: .reverse)
    private var txnRows: [StoredTransaction]
    @Query private var matchRows: [StoredMatch]
    @Query(sort: \StoredCategoryRule.sortOrder) private var ruleRows: [StoredCategoryRule]

    @State private var note = ""
    /// Which memo `note` was loaded for, so a re-render never clobbers what the
    /// user is typing and a different memo never inherits it.
    @State private var noteLoadedFor: String?
    @State private var offer: MeasuredOffer?
    @State private var ruleSaved = false

    private var memo: StoredPendingMemo? {
        memoRows.first { $0.captureHash == captureHash }
    }

    var body: some View {
        Group {
            if let memo {
                form(memo)
            } else {
                ContentUnavailableView("This memo is gone",
                                       systemImage: "tray",
                                       description: Text("It was merged into a statement row, or it expired after \(PendingMemo.expiryDays) days."))
            }
        }
        .navigationTitle("Review alert")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadNote() }
        .onChange(of: captureHash) { _, _ in loadNote() }
    }

    @ViewBuilder
    private func form(_ memo: StoredPendingMemo) -> some View {
        // The offer appears BELOW the category list, which is off-screen at the
        // moment the user taps a category — so the question they are meant to
        // answer would arrive unseen. Scrolling to it is what makes choosing a
        // category and being offered a rule feel like one action.
        ScrollViewReader { proxy in
            formBody(memo)
                .onChange(of: offer?.id) { _, id in
                    guard id != nil else { return }
                    withAnimation { proxy.scrollTo(Self.offerAnchor, anchor: .center) }
                }
        }
    }

    private static let offerAnchor = "memo-offer-anchor"

    @ViewBuilder
    private func formBody(_ memo: StoredPendingMemo) -> some View {
        Form {
            Section("Alert") {
                HStack {
                    Text("Amount").foregroundStyle(.secondary)
                    Spacer()
                    HisabTheme.amountText(memo.amountPaise, direction: memo.direction)
                }
                LabeledContent("Payee", value: memo.payee)
                if let vpa = memo.vpa { LabeledContent("UPI ID", value: vpa) }
                if let tail = memo.accountTail { LabeledContent("Account", value: "••\(tail)") }
                LabeledContent("Captured", value: ISTStamp.dayTime(memo.capturedAt))
            }

            Section("Note") {
                TextField("Optional — what was this for?", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .onSubmit { saveNote(memo) }
                    .onChange(of: note) { _, _ in saveNote(memo) }
            }

            Section {
                ForEach(categoryChoices, id: \.self) { category in
                    Button {
                        assign(category, to: memo)
                    } label: {
                        HStack {
                            Text(category)
                            Spacer()
                            if memo.assignedCategory == category {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(HisabTheme.khataRed)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    // See `NeedsReviewSection`: without this the row's empty
                    // middle is not a tap target.
                    .contentShape(Rectangle())
                    // Distinct from the same category name on the dashboard
                    // behind the sheet, which is what an automated tap on a
                    // bare "Groceries" finds first.
                    .accessibilityIdentifier("memo-category-\(category)")
                }
            } header: {
                Text("Category")
            } footer: {
                Text("The first few are what you spend on most; the rest are every category your rules already use. Nothing here touches your statements — a memo is a label. If its alert carried a bank reference, the payment is already in your ledger; if not, the memo stays a label until the statement arrives.")
            }

            if let offer {
                offerSection(offer).id(Self.offerAnchor)
            }
        }
        .accessibilityIdentifier("memo-review")
    }

    @ViewBuilder
    private func offerSection(_ offer: MeasuredOffer) -> some View {
        Section {
            if ruleSaved {
                Label("Rule saved. \(offer.count == 0 ? "No past transactions matched." : "\(offer.count) past \(offer.count == 1 ? "transaction" : "transactions") re-categorized.")",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(HisabTheme.hara)
            } else {
                Text("Always categorize “\(offer.pattern)” as \(offer.category)?")
                    .font(.headline)
                if offer.count > 0 {
                    Text("This will also update \(offer.count) past \(offer.count == 1 ? "transaction" : "transactions").")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Create rule") {
                    RuleOffers.createRule(pattern: offer.pattern, category: offer.category,
                                          existing: ruleRows, in: context)
                    CaptureNotifier.clearOffer(captureHash: offer.captureHash)
                    ruleSaved = true
                }
                .buttonStyle(.borderedProminent)
                .tint(HisabTheme.khataRed)
                Button("Not now") {
                    CaptureNotifier.clearOffer(captureHash: offer.captureHash)
                    self.offer = nil
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Remember this?")
        }
        .accessibilityIdentifier("memo-rule-offer")
    }

    // MARK: derived

    private var selfTransfers: Set<UUID> { Queries.selfTransferUUIDs(in: txnRows) }

    /// `CategoryRanker`'s three, then every other category the user's rules
    /// already use, alphabetically. The reserved names are not choices: two of
    /// them mean "no answer" and the third is assigned by reconciliation.
    private var categoryChoices: [String] {
        let matcher = Queries.matcher(from: ruleRows)
        let records = Queries.suggestionRecords(txnRows, matches: matchRows,
                                                matcher: matcher,
                                                selfTransfers: selfTransfers)
        let ranked = CategoryRanker.topCategories(records: records, now: Date(), limit: 3)
        let reserved: Set<String> = [Categorizer.uncategorized, Categorizer.miscellaneous,
                                     Categorizer.selfTransfer]
        var seen = Set(ranked)
        let rest = ruleRows.map(\.category)
            .filter { !reserved.contains($0) && seen.insert($0).inserted }
            .sorted()
        return ranked + rest
    }

    // MARK: actions

    private func loadNote() {
        guard noteLoadedFor != captureHash else { return }
        note = memo?.note ?? ""
        noteLoadedFor = captureHash
        offer = nil
        ruleSaved = false
    }

    private func saveNote(_ memo: StoredPendingMemo) {
        guard noteLoadedFor == captureHash else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard memo.note != value else { return }
        memo.note = value
        try? context.save()
    }

    private func assign(_ category: String, to memo: StoredPendingMemo) {
        saveNote(memo)
        MemoStore.assign(category: category, to: memo, in: context)
        let pattern = memo.asMemo.ruleKey.pattern
        guard !pattern.isEmpty else {
            offer = nil
            return
        }
        ruleSaved = false
        offer = MeasuredOffer(
            captureHash: memo.captureHash,
            pattern: pattern,
            category: category,
            count: RuleOffers.affectedCount(pattern: pattern, category: category,
                                            txns: txnRows, matches: matchRows,
                                            selfTransfers: selfTransfers,
                                            rules: Queries.rules(from: ruleRows)))
        // An offer the user is looking at supersedes one this memo queued from
        // a notification button; leaving both would ask the same question twice.
        CaptureNotifier.clearOffer(captureHash: memo.captureHash)
    }
}

// MARK: - the queued offer

/// The rule offer for a category chosen from a NOTIFICATION button, shown the
/// next time Hisab is opened.
///
/// A category button does not foreground the app, so the assignment lands in
/// the store while the question — "should this become a rule?" — has nowhere to
/// be asked. `CaptureNotifier.pendingRuleOffers` holds it until here.
struct RuleOfferSheet: View {
    let offer: CaptureNotifier.RuleOffer
    /// Called once the offer is resolved, so the root can present the next one.
    let onResolve: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \StoredPendingMemo.capturedAt, order: .reverse)
    private var memoRows: [StoredPendingMemo]
    @Query(sort: \StoredTransaction.date, order: .reverse)
    private var txnRows: [StoredTransaction]
    @Query private var matchRows: [StoredMatch]
    @Query(sort: \StoredCategoryRule.sortOrder) private var ruleRows: [StoredCategoryRule]

    private var memo: StoredPendingMemo? {
        memoRows.first { $0.captureHash == offer.captureHash }
    }

    private var pattern: String { memo?.asMemo.ruleKey.pattern ?? "" }

    private var count: Int {
        RuleOffers.affectedCount(pattern: pattern, category: offer.category,
                                 txns: txnRows, matches: matchRows,
                                 selfTransfers: Queries.selfTransferUUIDs(in: txnRows),
                                 rules: Queries.rules(from: ruleRows))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundStyle(HisabTheme.sona)
                if let memo {
                    Text("You filed \(Money.formatPaise(memo.amountPaise)) to \(memo.payee) as \(offer.category).")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                } else {
                    Text("You filed a payment as \(offer.category).")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                if pattern.isEmpty {
                    Text("That memo is gone, so there is nothing left to build a rule from.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Always categorize “\(pattern)” as \(offer.category)?")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    if count > 0 {
                        Text("This will also update \(count) past \(count == 1 ? "transaction" : "transactions").")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Create rule") {
                        RuleOffers.createRule(pattern: pattern, category: offer.category,
                                              existing: ruleRows, in: context)
                        resolve()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HisabTheme.khataRed)
                }
                Button(pattern.isEmpty ? "OK" : "Not now") { resolve() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .accessibilityIdentifier("queued-rule-offer")
        }
        .presentationDetents([.medium])
    }

    private func resolve() {
        CaptureNotifier.clearOffer(captureHash: offer.captureHash)
        onResolve()
        dismiss()
    }
}
