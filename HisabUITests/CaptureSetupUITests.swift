import XCTest

/// The capture setup screen's system check and parser test, through the real
/// UI. `--capture-alert` drives one alert through the real App Intent first,
/// standing in for a Shortcuts automation the simulator cannot run.
@MainActor
final class CaptureSetupUITests: XCTestCase {
    private let sample = "Rs.450.00 debited from a/c XX1234 on 22-09-26 to VPA vedant@okaxis. UPI Ref No 627775786529"

    override func setUp() {
        continueAfterFailure = false
    }

    private func openSetup(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--capture-enable", "--tab", "settings"] + arguments
        app.launch()
        let link = app.buttons["Capture setup"]
        XCTAssertTrue(link.waitForExistence(timeout: 30))
        link.tap()
        XCTAssertTrue(app.staticTexts["System check"].waitForExistence(timeout: 10))
        return app
    }

    func testSystemCheckReportsAWorkingPipeline() {
        let app = openSetup(["--capture-alert", sample])
        XCTAssertTrue(app.staticTexts["Capture is on"].exists)
        XCTAssertTrue(app.staticTexts["On-device reader works"].waitForExistence(timeout: 10))
        // The harness's alert is processed in a launch task that may finish
        // after the screen opened; the check re-runs each time it appears.
        // "Logged" on a fresh simulator, "already logged" on a rerun.
        let outcome = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The last alert was'"))
        for _ in 0..<5 where outcome.count == 0 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["Capture setup"].tap()
            _ = app.staticTexts["System check"].waitForExistence(timeout: 5)
        }
        XCTAssertEqual(outcome.count, 1)
        XCTAssertTrue(app.staticTexts["The automation is reaching Hisab"].exists)

        // At the bottom of a lazy list: not in the hierarchy until scrolled to.
        let testIt = app.buttons["Test it"].firstMatch
        for _ in 0..<10 where !testIt.isHittable { app.swipeUp() }
        testIt.tap()
        let result = app.staticTexts["capture-test-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertTrue(result.label.contains("₹450.00 out"), result.label)
        XCTAssertTrue(result.label.contains("ref 627775786529"), result.label)
        let reportReading = app.buttons["Report this reading"]
        for _ in 0..<3 where !reportReading.exists { app.swipeUp() }
        XCTAssertTrue(reportReading.exists)
    }

    func testACrashMidReadSwitchesTheReaderOffUntilRetried() {
        let app = openSetup(["--reader-crash-marker"])
        XCTAssertTrue(app.staticTexts["On-device reader crashed"].waitForExistence(timeout: 10))

        app.buttons["Try the reader again"].tap()
        XCTAssertTrue(app.staticTexts["On-device reader works"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["On-device reader crashed"].exists)
    }
}
