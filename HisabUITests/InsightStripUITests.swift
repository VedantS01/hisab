import XCTest
import HisabCore

/// The five things the insight strip has to do on a device, driven through the
/// real UI with the bundled demo statements. Nothing here reaches into the
/// engine: every assertion is something a person would see.
///
/// Suppressions live in UserDefaults and survive between test methods, so every
/// test launches with `--reset-insights` and then waits for the full baseline
/// strip before touching anything — the reset lands in a `.task`, one runloop
/// after the first render.
@MainActor
final class InsightStripUITests: XCTestCase {
    private let captions = ["TREND", "RECURRING", "COMMITTED", "UNUSUAL"]
    private let baseline = [
        "UNUSUAL. Blue Tokai: ₹1,250.00. about 4× your usual ₹300.00",
        "TREND. Food Delivery: ₹3,420.00. up 235% vs your 3-month average",
        "RECURRING. New recurring: Netflix. ₹649.00 per month since",
        "UNUSUAL. Zomato: ₹450.00 ×2. 2 identical payments on",
        "COMMITTED. ₹14,149.00 per month committed. across 3 recurring payments",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    /// `seedDemo: false` is reopening the app. `--seed-demo` is the harness
    /// standing in for a tap on "Load demo data", which now refreshes the demo
    /// — so anything checking that state survives a relaunch has to leave it
    /// out, or it is testing a reload rather than a relaunch.
    ///
    /// `legacyDemo: true` is the state a pre-1.2 user upgrades with: a demo
    /// imported the old way, under its file's byte hash rather than the
    /// `demo-<source>` slot key.
    @discardableResult
    private func launch(reset: Bool, seedDemo: Bool = true,
                        demoNow: String? = nil,
                        legacyDemo: Bool = false,
                        requireStrip: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (legacyDemo ? ["--seed-legacy-demo"] : [])
            + (seedDemo ? ["--seed-demo"] : [])
            + (reset ? ["--reset-insights"] : [])
            + (demoNow.map { ["--demo-now", $0] } ?? [])
        app.launch()
        if requireStrip {
            XCTAssertTrue(app.staticTexts["For you"].waitForExistence(timeout: 30))
        } else {
            // The caller is about to assert on stored documents, not on cards;
            // whether this particular seed still produces insights is not its
            // subject, and demanding a strip would fail it for the wrong reason.
            XCTAssertTrue(app.buttons["Buckets"].waitForExistence(timeout: 30))
        }
        dismissSuggestionPrompt(app)
        return app
    }

    /// Belt and braces. The demo statements no longer raise the rule-suggestion
    /// sheet (every merchant in the last 90 days categorises), but a stray
    /// uncategorised cluster would cover the dashboard and fail everything here
    /// for a reason that has nothing to do with the strip.
    private func dismissSuggestionPrompt(_ app: XCUIApplication) {
        let button = app.buttons["Don't ask about this"]
        if button.waitForExistence(timeout: 2) { button.tap() }
    }

    /// Cards carry a combined label: "<CAPTION>. <headline>. <detail>".
    private func labels(_ app: XCUIApplication) -> [String] {
        app.buttons.allElementsBoundByIndex
            .filter { $0.exists }
            .map { $0.label }
            .filter { label in captions.contains { label.hasPrefix("\($0). ") } }
    }

    private func card(_ app: XCUIApplication, _ prefix: String) -> XCUIElement? {
        app.buttons.allElementsBoundByIndex.first {
            $0.exists && $0.label.hasPrefix(prefix)
        }
    }

    /// Polls the strip: SwiftUI recomputes a frame or two after a suppression
    /// is written, so reading the labels straight after a tap is a race.
    @discardableResult
    private func waitForStrip(_ app: XCUIApplication, timeout: TimeInterval = 15,
                              _ message: String,
                              until predicate: ([String]) -> Bool) -> [String] {
        var shown = labels(app)
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(shown) && Date() < deadline {
            usleep(400_000)
            shown = labels(app)
        }
        XCTAssertTrue(predicate(shown), "\(message): \(shown)")
        return shown
    }

    private func waitForBaseline(_ app: XCUIApplication) -> [String] {
        waitForStrip(app, "baseline strip never settled") { shown in
            shown.count == baseline.count
                && zip(shown, self.baseline).allSatisfy { $0.hasPrefix($1) }
        }
    }

    func testStripShowsFiveCardsWithCommittedSpendLast() {
        let app = launch(reset: true)
        let shown = waitForBaseline(app)
        XCTAssertEqual(shown.count, 5, "strip should cap at five cards")
        XCTAssertTrue(shown.last?.hasPrefix("COMMITTED. ") == true,
                      "committed spend must be pinned last: \(shown)")
        // Every kind but recurringChanged fits; that one is the sixth card,
        // which testDismissingACardRemovesItAndItStaysGone brings into view.
        for caption in captions {
            XCTAssertTrue(shown.contains { $0.hasPrefix("\(caption). ") },
                          "no \(caption) card in \(shown)")
        }
    }

    func testTappingACardOpensTheEvidenceForThoseTransactions() {
        let app = launch(reset: true)
        _ = waitForBaseline(app)
        card(app, "UNUSUAL. Zomato")?.tap()

        XCTAssertTrue(app.navigationBars["Why this"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Transactions"].exists)
        XCTAssertEqual(app.staticTexts.allElementsBoundByIndex
            .filter { $0.label == "Zomato" }.count, 2)
        XCTAssertEqual(app.staticTexts.allElementsBoundByIndex
            .filter { $0.label == "₹450.00" }.count, 2)
        app.buttons["Close"].tap()

        // The committed card explains itself with series, not rows.
        card(app, "COMMITTED. ")?.tap()
        XCTAssertTrue(app.navigationBars["Why this"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Recurring payments"].exists)
        for merchant in ["Netflix", "Gym Membership", "HDFC Home Loan"] {
            XCTAssertTrue(app.staticTexts[merchant].exists, "missing \(merchant)")
        }
        app.buttons["Close"].tap()
    }

    func testDismissingACardRemovesItAndItStaysGoneAfterRelaunch() {
        let app = launch(reset: true)
        _ = waitForBaseline(app)
        // The ✕ is merged into the card's combined accessibility element, so
        // it is reached by position rather than by label.
        // The first card, so it is on screen: a coordinate tap lands on the
        // glass, and the strip scrolls horizontally rather than paging.
        let target = card(app, "UNUSUAL. Blue Tokai")
        XCTAssertNotNil(target)
        target?.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.17)).tap()
        XCTAssertFalse(app.navigationBars["Why this"].waitForExistence(timeout: 2),
                       "the ✕ opened the evidence sheet instead of dismissing")

        waitForStrip(app, "dismissed card still on the strip") { shown in
            !shown.contains { $0.hasPrefix("UNUSUAL. Blue Tokai") }
        }
        // Its slot goes to the sixth card the cap was hiding.
        waitForStrip(app, "the next card did not take the freed slot") { shown in
            shown.contains { $0.hasPrefix("RECURRING. Gym Membership: ₹1,800.00") }
        }

        app.terminate()
        let relaunched = launch(reset: false, seedDemo: false)
        waitForStrip(relaunched, "dismissal did not survive relaunch") { shown in
            shown.count == 5 && !shown.contains { $0.hasPrefix("UNUSUAL. Blue Tokai") }
        }
    }

    /// "Load demo data" is a button, and a user can come back to it next month.
    /// The statements are rewritten to the current month on every load, so if
    /// they were identified by the bytes actually imported, each new month's
    /// load would look like a new file and land a second copy. The proof that
    /// it does not: seed as-of a date months back, relaunch with today's
    /// anchor, and the strip must still be reporting the *older* months —
    /// unchanged, because the second load did nothing at all.
    /// A returning user: they loaded the demo months ago and tap it again.
    /// The second tap must hand them a demo anchored to *today*, and hand them
    /// exactly one — the old one dropped, not left alongside.
    func testLoadingTheDemoAgainRefreshesItToToday() {
        let app = launch(reset: true, demoNow: "2026-06-15")
        let stale = waitForStrip(app, "strip never settled on the old anchor") {
            !$0.isEmpty
        }
        // Demo data three months old has aged out of the anomaly and recurrence
        // windows — which is the whole reason this must refresh rather than
        // no-op. If this ever stops being true the test below proves less.
        XCTAssertLessThan(stale.count, baseline.count,
                          "a stale demo was expected to be a thin strip: \(stale)")

        app.terminate()
        let refreshed = launch(reset: false)
        let after = waitForBaseline(refreshed)

        // Exact copy, so any row left behind by the old anchor shows up here:
        // the stale Netflix payments would extend that series backwards, its
        // first-seen month would fall outside the "new recurring" window, and
        // this card would be gone.
        XCTAssertTrue(after.contains { $0.hasPrefix("RECURRING. New recurring: Netflix") },
                      "orphaned rows from the previous anchor: \(after)")
        // And it is anchored to today: the duplicate lands in last month.
        let lastMonth = YearMonth(date: Date()).advanced(by: -1).displayName
        XCTAssertTrue(after.contains { $0.hasSuffix("identical payments on 28 \(lastMonth)") },
                      "demo was not re-anchored to today: \(after)")
    }

    /// The 1.1 -> 1.2 upgrade path. A user who tapped "Load demo data" before
    /// this release has demo documents stored under the SHA-256 of the bundled
    /// file, not the `demo-<source>` slot key 1.2 identifies them by. If
    /// `eraseExisting` doesn't recognise that older identity it erases nothing,
    /// the import guard doesn't fire either, and the next tap lands a *second*
    /// demo set alongside the first.
    ///
    /// The observable is the document list behind a coverage cell: one
    /// `demo-gpay.csv`, not two, and no empty document left over from a
    /// fully-deduplicated second import.
    func testLoadingTheDemoCleansUpAPre12Demo() {
        // Arrive as an upgrading user: the old demo, the old identity, and no
        // 1.2 load yet.
        let seeded = launch(reset: true, seedDemo: false, legacyDemo: true,
                            requireStrip: false)
        let month = YearMonth(date: Date())
        openCoverageDocuments(seeded, source: "gpay", month: month,
                              message: "the legacy demo did not seed")
        XCTAssertEqual(documentRows(seeded, named: "demo-gpay.csv"), 1,
                       "the legacy seed itself should be one document")
        seeded.buttons["Done"].tap()
        seeded.terminate()

        // Upgrade in place and tap "Load demo data".
        let refreshed = launch(reset: false, seedDemo: true)
        openCoverageDocuments(refreshed, source: "gpay", month: month,
                              message: "no GPay coverage after the refresh")
        XCTAssertEqual(documentRows(refreshed, named: "demo-gpay.csv"), 1,
                       "the pre-1.2 demo was left behind and a second one "
                       + "imported on top of it")
        // A second import whose rows all deduplicate against the first leaves a
        // document with nothing in it — the quiet shape of the same bug.
        XCTAssertFalse(refreshed.staticTexts.allElementsBoundByIndex
            .contains { $0.exists && $0.label.contains("· 0 transactions") },
                       "a demo document survived with no transactions")
        refreshed.buttons["Done"].tap()
    }

    /// Buckets -> the coverage cell for one source and month -> its documents.
    private func openCoverageDocuments(_ app: XCUIApplication, source: String,
                                       month: YearMonth, message: String) {
        app.buttons["Buckets"].tap()
        let cell = app.buttons["coverage-\(source)-\(month)"]
        // Also the horizon guard: the demo statements carry fixed dates and
        // the loader slides them onto the current month, so the legacy (unshifted)
        // and refreshed sets only share a month while that slide is smaller than
        // the demo's own span. If this ever fails, the demo CSVs need re-anchoring
        // — the test is telling you the fixture aged out, not that the fix broke.
        XCTAssertTrue(cell.waitForExistence(timeout: 10), message)
        cell.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "the document list did not open")
    }

    private func documentRows(_ app: XCUIApplication, named filename: String) -> Int {
        app.staticTexts.allElementsBoundByIndex
            .filter { $0.exists && $0.label == filename }
            .count
    }

    func testLongPressOffersMuteAndMutingSilencesThatMerchant() {
        let app = launch(reset: true)
        _ = waitForBaseline(app)
        card(app, "UNUSUAL. Blue Tokai")?.press(forDuration: 1.2)

        let mute = app.buttons["Don't show insights like this"]
        XCTAssertTrue(mute.waitForExistence(timeout: 5), "no mute action on long press")
        mute.tap()

        waitForStrip(app, "muted merchant still produces a card") { shown in
            !shown.contains { $0.hasPrefix("UNUSUAL. Blue Tokai") }
        }
    }
}
