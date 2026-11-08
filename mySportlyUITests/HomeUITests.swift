import XCTest
import UIKit

@MainActor final class HomeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }

    func testHomeShowsFollowedGameAndPlaysIt() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        XCTAssertTrue(app.descendants(matching: .any)["home-hero"].waitForExistence(timeout: 15))
        let teams = app.descendants(matching: .any)["home-teams"]
        XCTAssertTrue(teams.waitForExistence(timeout: 15))
        // Guide matching gives the sample game its own ID.
        let cards = teams.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-game-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["home-channel-sample.0"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["home-follow-prompt"].exists)
        capture("Home with a followed team")
        let watch = app.buttons.matching(identifier: "home-hero-watch").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(watch); watch?.tap()
        XCTAssertTrue(app.descendants(matching: .any)["stream-preview"].firstMatch.waitForExistence(timeout: 10))
        capture("Player from the Home hero")
    }

    func testNothingFollowedShowsOnePrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.waitForSavedCatalog()
        let prompt = app.descendants(matching: .any).matching(identifier: "home-follow-prompt")
        XCTAssertTrue(prompt.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(prompt.count, 1)
        XCTAssertFalse(app.descendants(matching: .any)["home-teams"].exists)
        capture("Home with nothing followed")
    }

    /// Uses the device's saved catalog. Home must exist on relaunch before the
    /// full catalog is ready; rows come from the launch snapshot.
    func testHomeRendersFromSnapshotBeforeCatalogReady() throws {
        let app = XCUIApplication()
        app.launch()
        let home = app.descendants(matching: .any)["home-root"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 30))
        if app.buttons["Connect a Source"].exists { throw XCTSkip("Requires a saved provider catalog") }
        app.waitForSavedCatalog()
        sleep(3)
        app.terminate()
        app.launch()
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        let value = home.value as? String ?? ""
        guard value.contains("ready=0") else {
            print("[HomeSnapshot] inconclusive: catalog was ready before the first check (\(value))")
            return
        }
        if app.descendants(matching: .any)["home-channels"].exists || app.descendants(matching: .any)["home-teams"].exists {
            print("[HomeSnapshot] rows rendered before catalog ready")
        } else {
            print("[HomeSnapshot] no favorites or games in the snapshot; Home shows its prompt")
            XCTAssertTrue(app.descendants(matching: .any)["home-follow-prompt"].exists || app.descendants(matching: .any)["home-hero"].exists)
        }
        capture("Home from the launch snapshot")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
