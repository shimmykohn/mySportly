import XCTest
import UIKit

@MainActor final class LineupFilteringUITests: XCTestCase {
    func testNativeGuideLineupFilter() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.selectMainTab("Guide")
        let count = app.staticTexts["guide-channel-count"].firstMatch
        // Sample News HD and SD share a guide ID: one channel with two feeds.
        assertValue(count, "3")
        app.selectLineup("All Channels")
        assertValue(count, "6")
        app.selectLineup("Unclassified")
        assertValue(count, "1")
        app.selectLineup("My Lineup")
        assertValue(count, "3")
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
