import XCTest
import UIKit

@MainActor final class LineupFilteringUITests: XCTestCase {
    func testNativeLineupFilterIsSharedWithSearchAndGuideStatus() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.selectMainTab("Guide")
        let count = app.staticTexts["guide-channel-count"].firstMatch
        assertValue(count, "4")
        app.selectLineup("All Channels")
        assertValue(count, "7")
        app.selectLineup("Unclassified")
        assertValue(count, "1")
        app.selectLineup("My Lineup")
        assertValue(count, "4")
        app.buttons["Guide Filters"].firstMatch.tap()
        let status = app.buttons["TV Guide Status"].firstMatch
        if !status.isHittable { app.swipeUp() }
        status.tap()
        capture("Guide status navigation")
        XCTAssertTrue(app.navigationBars["TV Guide Status"].waitForExistence(timeout: 5))
        capture("Native guide status opened")
        assertValue(app.staticTexts["guide-status-channels"].firstMatch, "4")
        assertValue(app.staticTexts["guide-status-matched"].firstMatch, "4")
        capture("Native guide coverage")
        app.buttons["BackButton"].firstMatch.tap()
        app.buttons["close-guide-options"].tap()
        app.selectMainTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("now")
        let matches = app.staticTexts["search-result-count"].firstMatch
        assertValue(matches, "4")
        if app.keyboards.count > 0 { field.typeText("\n") }
        app.selectLineup("All Channels")
        assertValue(matches, "7")
        app.selectMainTab("Guide")
        assertValue(count, "7")
        app.selectLineup("My Lineup")
        assertValue(count, "4")
        capture("Native preferred lineup")
    }
    private func assertValue(_ element: XCUIElement, _ value: String) {
        let ready = NSPredicate { _, _ in element.exists && element.value as? String == value }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 15), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
