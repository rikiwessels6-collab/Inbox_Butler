import XCTest

/// Launches the real app in the simulator (demo data) and taps through the main
/// screens. Catches crashes and broken screens that compiling alone cannot.
final class SmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func text(_ app: XCUIApplication, containing s: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
    }

    /// Skips the first-run welcome screen (it is tested separately below).
    private func launchPastWelcome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenWelcome", "YES", "-hasSeenTour", "YES"]
        app.launch()
        return app
    }

    func testFirstLaunchShowsTheWelcomeScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["welcome-google"].waitForExistence(timeout: 30), "Welcome screen missing")
        XCTAssertTrue(app.buttons["welcome-icloud"].exists)
        app.buttons["welcome-demo"].tap()
        // The guided tour follows: step through every page.
        XCTAssertTrue(app.buttons["tour-continue"].waitForExistence(timeout: 30), "Tour did not start")
        for _ in 0..<5 {
            app.buttons["tour-continue"].tap()
            _ = app.buttons["tour-continue"].waitForExistence(timeout: 5) || app.buttons["tour-done"].waitForExistence(timeout: 5)
        }
        XCTAssertTrue(app.buttons["tour-done"].waitForExistence(timeout: 10), "Tour did not reach its last page")
        app.buttons["tour-done"].tap()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30), "App did not open after the tour")
    }

    func testLaunchShowsInboxAndMainTabs() {
        let app = launchPastWelcome()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30), "App did not launch to the tab bar")

        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected)
        app.buttons["Needs action"].tap()
        XCTAssertTrue(app.navigationBars["Needs action"].waitForExistence(timeout: 10))
        app.navigationBars["Needs action"].buttons["Done"].tap()
        app.tabBars.buttons["Inbox"].tap()
        // Demo mail is listed.
        XCTAssertTrue(text(app, containing: "Sam Rivera").waitForExistence(timeout: 30), "Demo inbox did not load")

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Mail accounts"].tap()
        XCTAssertTrue(text(app, containing: "demo accounts").waitForExistence(timeout: 10))

        app.buttons["Done"].tap()
        XCTAssertTrue(text(app, containing: "priority senders").waitForExistence(timeout: 10))
    }

    func testOpeningAMessageFindsTheSuggestedEvent() {
        let app = launchPastWelcome()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30))
        app.tabBars.buttons["Inbox"].tap()
        let row = text(app, containing: "Appointment confirmed")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Demo appointment email missing")
        row.tap()
        // Reads the body and the .ics attachment on-device and proposes the event.
        XCTAssertTrue(app.buttons["Add to Calendar"].waitForExistence(timeout: 30), "No suggested event appeared")
    }
}
