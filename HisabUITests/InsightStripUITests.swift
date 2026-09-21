import XCTest

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

    @discardableResult
    private func launch(reset: Bool, demoNow: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
            + (reset ? ["--reset-insights"] : [])
            + (demoNow.map { ["--demo-now", $0] } ?? [])
        app.launch()
        XCTAssertTrue(app.staticTexts["For you"].waitForExistence(timeout: 30))
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
        let relaunched = launch(reset: false)
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
    func testLoadingTheDemoAgainInALaterMonthChangesNothing() {
        // Deliberately asserts the invariant rather than a fixed month: this
        // suite shares one simulator, so by the time it runs the demo may
        // already be loaded under some other anchor — which is exactly the
        // state a returning user is in, and the state this must hold in.
        let app = launch(reset: true, demoNow: "2026-06-15")
        let before = waitForStrip(app, "strip never settled on the first anchor") {
            $0.count == self.baseline.count
        }
        XCTAssertTrue(before.last?.hasPrefix("COMMITTED. ") == true)

        app.terminate()
        let again = launch(reset: false, demoNow: "2027-01-20")
        let after = waitForStrip(again, "strip never settled after the second load") {
            $0.count == self.baseline.count
        }
        XCTAssertEqual(after, before,
                       "a demo load anchored seven months on changed the data")
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
