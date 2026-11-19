import XCTest
import UIKit

final class mySportlyUITests: XCTestCase {
    @MainActor override func setUpWithError() throws {
        continueAfterFailure = false
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    @MainActor func testSampleCatalogNavigationAndNativeSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["home-root"].waitForExistence(timeout: 15))
        capture("Home", app: app)
        app.buttons["home-profile"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let rows = ["Sources", "Region and Language", "Appearance", "Sync Personal Choices", "OpenAI"]
        for row in rows { XCTAssertTrue(app.descendants(matching: .any)[row].firstMatch.exists, "Missing Settings row: \(row)") }
        for removed in ["Automatic Refresh", "Interests and Sports", "Sports Data", "Where Data Comes From", "Open To", "Use Viewing History", "Manage Recordings"] {
            XCTAssertFalse(app.descendants(matching: .any)[removed].firstMatch.exists, "Settings still shows \(removed)")
        }
        app.buttons["Region and Language"].tap()
        XCTAssertTrue(app.navigationBars["Region and Language"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.openGuide()
        XCTAssertTrue(app.buttons["Guide Time"].waitForExistence(timeout: 5))
        capture("Guide", app: app)
        app.selectMainTab("My Stuff")
        XCTAssertTrue(app.navigationBars["My Stuff"].waitForExistence(timeout: 5))
        capture("My Stuff", app: app)
        app.selectMainTab("Search")
        capture("Search", app: app)
    }

    @MainActor func testIPadTimeline() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "This layout requires an iPad.")
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["home-root"].waitForExistence(timeout: 15))
        app.openGuide()
        let timeline = app.switches["Timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        // The native Toggle exposes its entire wide label row to accessibility;
        // tap the trailing switch rather than the inert space in the row's center.
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(timeline.value as? String, "1")
        capture("iPad Guide Timeline", app: app)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
