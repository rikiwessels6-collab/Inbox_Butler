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
        app.launchArguments += ["-hasSeenWelcome", "YES"]
        app.launch()
        return app
    }

    func testFirstLaunchShowsTheWelcomeScreen() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Continue with Google"].waitForExistence(timeout: 30), "Welcome screen missing")
        XCTAssertTrue(app.buttons["Continue with iCloud"].exists)
        app.buttons["Look around with demo mail"].tap()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30), "App did not open after the welcome")
    }

    func testLaunchShowsInboxAndMainTabs() {
        let app = launchPastWelcome()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30), "App did not launch to the tab bar")

        // Demo mail is listed.
        XCTAssertTrue(text(app, containing: "Sam Rivera").waitForExistence(timeout: 30), "Demo inbox did not load")

        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(text(app, containing: "demo accounts").waitForExistence(timeout: 10))

        app.tabBars.buttons["Priority"].tap()
        XCTAssertTrue(text(app, containing: "priority senders").waitForExistence(timeout: 10))
    }

    func testOpeningAMessageFindsTheSuggestedEvent() {
        let app = launchPastWelcome()
        XCTAssertTrue(app.tabBars.buttons["Inbox"].waitForExistence(timeout: 30))
        let row = text(app, containing: "Appointment confirmed")
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Demo appointment email missing")
        row.tap()
        // Reads the body and the .ics attachment on-device and proposes the event.
        XCTAssertTrue(app.buttons["Add to Calendar"].waitForExistence(timeout: 30), "No suggested event appeared")
    }
}
