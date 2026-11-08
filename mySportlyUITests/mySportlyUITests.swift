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
        XCTAssertTrue(app.staticTexts["Sample catalog and schedule"].waitForExistence(timeout: 15))
        capture("Live", app: app)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Languages and Regions"].tap()
        XCTAssertTrue(app.navigationBars["Languages and Regions"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.selectMainTab("Guide")
        XCTAssertTrue(app.buttons["Now"].waitForExistence(timeout: 5))
        capture("Guide", app: app)
        app.selectMainTab("Sports")
        XCTAssertTrue(app.switches["Teams and Leagues I Follow"].waitForExistence(timeout: 5))
        capture("Sports", app: app)
        app.selectMainTab("Library")
        XCTAssertTrue(app.buttons["Recordings"].waitForExistence(timeout: 5))
        capture("Library", app: app)
    }

    @MainActor func testOrganizerCanReviewSampleMetadataWithoutCloudAI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Sample catalog and schedule"].waitForExistence(timeout: 15))
        for _ in 0..<6 where !app.buttons["Organize Channels"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["Organize Channels"].exists)
        app.buttons["Organize Channels"].tap()
        XCTAssertTrue(app.navigationBars["Organizer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select Confident Suggestions"].exists)
        capture("Organizer", app: app)
    }

    @MainActor func testIPadTimelineAndTwoStreamMultiview() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "This layout requires an iPad.")
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Sample catalog and schedule"].waitForExistence(timeout: 15))
        app.selectMainTab("Guide")
        let timeline = app.switches["Timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        // The native Toggle exposes its entire wide label row to accessibility;
        // tap the trailing switch rather than the inert space in the row's center.
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(timeline.value as? String, "1")
        capture("iPad Guide Timeline", app: app)
        app.selectMainTab("Live")
        XCTAssertTrue(app.navigationBars["Live"].waitForExistence(timeout: 5))
        for _ in 0..<6 where !app.buttons["Open Multiview"].isHittable { app.swipeUp() }
        app.buttons["Open Multiview"].tap()
        for name in ["Sample News HD", "Sample Sports"] {
            app.buttons["Add Channel"].tap()
            let channel = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            XCTAssertTrue(channel.waitForExistence(timeout: 5))
            channel.tap()
        }
        XCTAssertEqual(app.buttons.matching(identifier: "Audio On").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "Listen").count, 1)
        app.buttons["Listen"].tap()
        capture("iPad Multiview", app: app)
        app.buttons["Done"].tap()
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
