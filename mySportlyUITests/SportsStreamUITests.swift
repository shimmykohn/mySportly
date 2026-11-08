import XCTest
import UIKit

@MainActor final class SportsStreamUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testHomeGameAndTeamPageGamePlay() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        let homeGame = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-game-'")).firstMatch
        XCTAssertTrue(homeGame.waitForExistence(timeout: 15))
        capture("Home - followed team's live game")
        homeGame.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        waitForVideo(preview)
        capture("Home game - first video frame")
        app.buttons["close-player"].tap()
        app.buttons["Stop"].firstMatch.tap()
        // The same game is reachable from the team's page in My Stuff.
        app.selectMainTab("My Stuff")
        let team = app.buttons["my-stuff-team-New York Knicks"].firstMatch
        XCTAssertTrue(team.waitForExistence(timeout: 10)); team.tap()
        let game = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-game-'")).firstMatch
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        capture("Team page - live game")
        game.tap()
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
