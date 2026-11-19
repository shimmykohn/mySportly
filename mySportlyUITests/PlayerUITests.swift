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

    func testWatchTwoPlaysASecondStreamWithOneSound() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        let channel = app.buttons["home-channel-sample.0"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        channel.tap()
        let add = app.buttons["add-second-stream"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Movies")
        let movies = app.buttons["second-channel-sample.3"].firstMatch
        XCTAssertTrue(movies.waitForExistence(timeout: 5))
        movies.tap()
        let second = app.descendants(matching: .any)["second-stream"].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        let ready = NSPredicate { _, _ in second.value as? String == "Video ready" }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 35), .completed)
        let sound = app.buttons["second-sound"].firstMatch
        XCTAssertEqual(sound.label, "Sound Off", "The second stream starts muted")
        sound.tap()
        XCTAssertTrue(app.buttons["Sound On"].waitForExistence(timeout: 3))
        capture("Watch two portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(second.waitForExistence(timeout: 5), "Landscape shows both side by side")
        capture("Watch two landscape")
        XCUIDevice.shared.orientation = .portrait
        let close = app.buttons["close-second-stream"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["player-title"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
