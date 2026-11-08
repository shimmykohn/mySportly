import XCTest
import UIKit

@MainActor final class SportsStreamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testGuideGameFeedPickerAndNativePlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("Sports")
        let game = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 15))
        capture("Sports - grouped guide game")
        game.tap()
        let watch = app.buttons["watch-sports-game"]
        XCTAssertTrue(watch.waitForExistence(timeout: 10))
        XCTAssertTrue(watch.isEnabled)
        let gamePicker = app.buttons["game-stream-picker"]
        reveal(gamePicker, app: app); gamePicker.tap()
        app.buttons["Sample Sports Alternate HD"].tap()
        capture("Sports - native game stream picker selection")
        watch.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        waitForVideo(preview)
        capture("Sports - first video frame")
        let picker = app.buttons["player-stream-picker"]
        reveal(picker, app: app); picker.tap()
        app.buttons["Sample Sports"].tap()
        waitForVideo(preview)
        XCTAssertTrue(picker.label.contains("Sample Sports") || (picker.value as? String)?.contains("Sample Sports") == true)
        let quality = app.buttons["player-quality-picker"]
        reveal(quality, app: app); quality.tap()
        app.buttons["Up to 720p"].tap()
        XCTAssertTrue(quality.label.contains("720p") || (quality.value as? String)?.contains("720p") == true)
        capture("Sports - native feed and quality controls")
        app.buttons["close-player"].tap()
        app.buttons["Stop"].firstMatch.tap()
        // The same game is reachable under a team and under its league.
        let team = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New York Knicks")).firstMatch
        reveal(team, app: app); team.tap()
        XCTAssertTrue(app.buttons["save-sports-item"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch.waitForExistence(timeout: 10))
        capture("Sports - game on team page")
        app.buttons["BackButton"].firstMatch.tap()
        let league = app.buttons["NBA"].firstMatch
        reveal(league, app: app); league.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch.waitForExistence(timeout: 10))
        capture("Sports - game on league page")
    }
    func testSavedGuideDisplaysGroupedGames() throws {
        let app = XCUIApplication(); app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("Sports")
        app.segmentedControls["sports-scope"].buttons["All Sports"].tap()
        let game = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sports-game-'")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 20), "Requires the saved current guide checked by SportsDataDeviceTests")
        capture("Sports - saved provider games and cached logos")
        game.tap()
        XCTAssertTrue(app.buttons["game-stream-picker"].waitForExistence(timeout: 10))
        capture("Sports - saved provider game feeds")
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
