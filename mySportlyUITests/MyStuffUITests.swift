import XCTest
import UIKit

@MainActor final class MyStuffUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testFollowTeamAppearsInMyStuffAndHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("My Stuff")
        XCTAssertTrue(app.staticTexts["Nothing Here Yet"].waitForExistence(timeout: 10))
        app.buttons["my-stuff-add"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Knicks")
        let follow = app.buttons["follow-New York Knicks"].firstMatch
        XCTAssertTrue(follow.waitForExistence(timeout: 5)); follow.tap()
        XCTAssertTrue(app.buttons["Following New York Knicks"].waitForExistence(timeout: 5))
        capture("Follow picker")
        // While searching, the bar shows Close instead of the toolbar's Done.
        if !app.buttons["Done"].isHittable { app.navigationBars.buttons["Close"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        let team = app.buttons["my-stuff-team-New York Knicks"].firstMatch
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        capture("My Stuff with a followed team")
        team.tap()
        XCTAssertTrue(app.switches["team-notify"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-game-'")).firstMatch.waitForExistence(timeout: 10))
        capture("Team page")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.selectMainTab("Home")
        XCTAssertTrue(app.descendants(matching: .any)["home-teams"].waitForExistence(timeout: 10))
        app.selectMainTab("My Stuff")
        app.revealSwipeAction("Unfollow", on: team)
        XCTAssertTrue(team.waitForNonExistence(timeout: 5))
    }

    func testFavoriteChannelAppearsAndRemoves() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("My Stuff")
        let channel = app.buttons["my-stuff-channel-sample.0"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["my-stuff-league-NBA"].exists)
        capture("My Stuff sections")
        app.revealSwipeAction("Remove Favorite", on: channel)
        XCTAssertTrue(channel.waitForNonExistence(timeout: 5))
        app.selectMainTab("Home")
        XCTAssertFalse(app.buttons["home-channel-sample.0"].exists)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
