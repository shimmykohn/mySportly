import XCTest
import UIKit

@MainActor final class PlayerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testPlayerOpensMinimizesAndRestores() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        let channel = app.buttons["home-channel-sample.0"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        channel.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        let ready = NSPredicate { _, _ in preview.value as? String == "Video ready" }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 35), .completed)
        let title = app.staticTexts["player-title"].firstMatch
        XCTAssertTrue(title.exists)
        let before = title.value as? String ?? ""
        XCTAssertEqual(before, "sample.0")
        capture("Player portrait")
        XCTAssertFalse(app.buttons["Next Channel"].exists, "The player has no channel stepping")
        XCTAssertFalse(app.buttons["Previous Channel"].exists, "The player has no channel stepping")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(title.waitForNonExistence(timeout: 5), "Landscape shows only the video")
        capture("Player landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["close-player"].tap()
        let mini = app.descendants(matching: .any)["compact-player"].firstMatch
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        capture("Mini player")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Open player for'")).firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
