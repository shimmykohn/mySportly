import XCTest
import UIKit

@MainActor final class SportsStreamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testHomeGamePlaysAndGamePageFeedPicker() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        let homeGame = app.buttons["home-game-sample.game"].firstMatch
        XCTAssertTrue(homeGame.waitForExistence(timeout: 15))
        capture("Home - followed team's live game")
        homeGame.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        waitForVideo(preview)
        capture("Home game - first video frame")
        let picker = app.buttons["player-stream-picker"]
        reveal(picker, app: app); picker.tap()
        app.buttons["Sample Sports Alternate HD"].tap()
        waitForVideo(preview)
        XCTAssertTrue(picker.label.contains("Alternate") || (picker.value as? String)?.contains("Alternate") == true)
        let quality = app.buttons["player-quality-picker"]
        reveal(quality, app: app); quality.tap()
        app.buttons["Up to 720p"].tap()
        XCTAssertTrue(quality.label.contains("720p") || (quality.value as? String)?.contains("720p") == true)
        capture("Player - native feed and quality controls")
        app.buttons["close-player"].tap()
        app.buttons["Stop"].firstMatch.tap()
        // The same game is reachable from the team's page in My Stuff.
        app.selectMainTab("My Stuff")
        let team = app.buttons["library-item-New York Knicks"].firstMatch
        XCTAssertTrue(team.waitForExistence(timeout: 10)); team.tap()
        let game = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        capture("Team page - game")
        game.tap()
        let watch = app.buttons["watch-sports-game"]
        XCTAssertTrue(watch.waitForExistence(timeout: 10))
        XCTAssertTrue(watch.isEnabled)
        let gamePicker = app.buttons["game-stream-picker"]
        reveal(gamePicker, app: app); gamePicker.tap()
        app.buttons["Sample Sports Alternate HD"].tap()
        capture("Game page - native stream picker selection")
        watch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        waitForVideo(preview)
    }
    private func waitForVideo(_ preview: XCUIElement) {
        let ready = NSPredicate { _, _ in preview.value as? String == "Video ready" }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 35), .completed)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let playerList = app.collectionViews["player-details"].firstMatch
        for _ in 0..<5 {
            if element.isHittable { return }
            if playerList.exists {
                // On iPad the center of the app is inside the video. Scroll
                // the actual native List, not the AVKit surface above it.
                let start = playerList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                let end = playerList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                start.press(forDuration: 0.05, thenDragTo: end)
            } else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
