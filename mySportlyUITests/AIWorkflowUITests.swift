import XCTest
import UIKit

@MainActor final class AIWorkflowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testNativeAISettingsAndPersonalCategory() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        app.launch(); app.waitForSavedCatalog()
        openAISettings(app)
        capture("Native AI settings")
        let categories = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Your Categories")).firstMatch
        XCTAssertTrue(categories.waitForExistence(timeout: 8)); categories.tap()
        let add = app.buttons["add-ai-category"]
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.exists); add.tap()
        let path = app.textFields["ai-category-path"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { path.tap() }
        path.typeText("Learning / Astronomy")
        app.buttons["save-ai-category"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Astronomy")).firstMatch.waitForExistence(timeout: 8))
        capture("Personal category choices")
    }
    func testSystemLiveActivityBackgroundProgressAndPauseResume() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--demo-organization-progress"]
        app.launch(); app.waitForSavedCatalog()
        XCTAssertTrue(app.activityIndicators["live-loading"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["organization-progress-count"].exists, "Live header contains only its spinner")
        capture("Jev spinner in soft header")
        openAISettings(app)
        let count = app.staticTexts["organization-progress-count"]
        for _ in 0..<5 where !count.isHittable { app.swipeUp() }
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let progress = app.progressIndicators["organization-progress"]
        let background = NSPredicate(format: "value CONTAINS %@", "background running")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: background, object: progress)], timeout: 12), .completed, "Actual continued background processing must be granted")
        let before = count.label
        capture("Organization progress in AI settings")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Real wall-clock work progresses while the sample app is backgrounded.
        let wait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in false }, object: nil)
        _ = XCTWaiter.wait(for: [wait], timeout: 10)
        capture("System organization Live Activity")
        XCTAssertTrue(springboard.exists)
        app.activate()
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertNotEqual(count.label, before, "Background progress must advance")
        // The expanded system Live Activity can cover the app after activation.
        // A tap below it collapses that presentation before the native controls.
        if !app.buttons["pause-organization"].isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        capture("Returned from background")
        app.buttons["pause-organization"].tap()
        XCTAssertTrue(app.buttons["resume-organization"].waitForExistence(timeout: 5))
        let paused = count.label
        app.buttons["resume-organization"].tap()
        XCTAssertTrue(app.buttons["pause-organization"].waitForExistence(timeout: 8))
        XCTAssertEqual(count.label, paused, "Resume must retain completed work")
        capture("Resumed saved progress")
        app.buttons["pause-organization"].tap()
    }
    private func openAISettings(_ app: XCUIApplication) {
        app.buttons["Settings"].firstMatch.tap()
        let ai = app.buttons["ai-settings"].firstMatch
        for _ in 0..<4 where !ai.isHittable { app.swipeUp() }
        XCTAssertTrue(ai.waitForExistence(timeout: 10)); ai.tap()
        XCTAssertTrue(app.navigationBars["AI"].waitForExistence(timeout: 8))
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
