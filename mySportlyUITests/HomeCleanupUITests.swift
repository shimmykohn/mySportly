import XCTest
import UIKit

@MainActor final class HomeCleanupUITests: XCTestCase {
    func testSportFeedsGroupOnHomeAndInSports() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sport-groups"]
        app.launch()
        let golf = app.buttons["sport-group-golf"].firstMatch
        let tennis = app.buttons["sport-group-tennis"].firstMatch
        app.waitForSavedCatalog()
        for _ in 0..<5 where !golf.isHittable { app.swipeUp() }
        XCTAssertTrue(golf.isHittable)
        XCTAssertFalse(app.buttons["play-channel-sample.golf.1"].exists)
        capture("Grouped sports on Live")
        golf.tap()
        XCTAssertTrue(app.buttons["play-channel-sample.golf.1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["play-channel-sample.tennis.1"].exists)
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("10")
        XCTAssertTrue(app.buttons["play-channel-sample.golf.10"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["play-channel-sample.golf.1"].waitForNonExistence(timeout: 5))
        capture("Golf group search")
        // Relaunch clears only this temporary navigation state; no source or
        // personal data is modified by the sample fixture.
        app.terminate(); app.launch()
        app.selectMainTab("Sports")
        let allSports = app.buttons["All Sports"].firstMatch
        if allSports.exists { allSports.tap() }
        XCTAssertTrue(app.buttons["manage-sports-following"].waitForExistence(timeout: 10))
        let groups = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Browse by Sport")).firstMatch
        XCTAssertTrue(groups.waitForExistence(timeout: 10)); groups.tap()
        for _ in 0..<5 where !tennis.isHittable { app.swipeUp() }
        tennis.tap()
        XCTAssertTrue(app.buttons["play-channel-sample.tennis.1"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["play-channel-sample.golf.1"].exists)
        capture("Tennis channels from Sports")
    }

    func testInterestsFilterMenuAndDiscoveredLeagueGroups() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sport-groups", "--demo-no-sports-interest"]
        app.launch(); app.waitForSavedCatalog()
        let sports = app.buttons["category-group-Sports"].firstMatch
        XCTAssertTrue(sports.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["sport-group-golf"].exists)
        XCTAssertFalse(app.navigationBars["Live"].exists)
        XCTAssertFalse(app.buttons["lineup-scope"].exists)
        capture("Live categories with News as an interest")
        app.selectLineup("All Channels")
        app.buttons["live-filters"].tap()
        let edit = app.buttons["Edit Interests"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let toggle = app.switches["interest-Sports"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["BackButton"].firstMatch.tap()
        let football = app.buttons["sport-group-football"].firstMatch
        for _ in 0..<6 where !football.isHittable { app.swipeUp() }
        XCTAssertTrue(football.isHittable)
        XCTAssertFalse(sports.exists)
        capture("Live interested Sports expanded")
        football.tap()
        XCTAssertTrue(app.buttons["provider-group-NFL"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["provider-group-NCAAF"].exists)
        let discovered = app.buttons["provider-group-NEWLEAGUE"]
        XCTAssertTrue(discovered.exists)
        capture("American Football source label groups")
        discovered.tap()
        XCTAssertTrue(app.buttons["play-channel-sample.newleague.1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["play-channel-sample.nfl.1"].exists)
        capture("Automatically discovered league streams")
    }

    func testRecentSwipeRemovesOnlyOneHistoryEntry() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-check"]
        app.launch()
        let first = app.buttons["recent-channel-sample.0"].firstMatch
        let second = app.buttons["recent-channel-sample.2"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20))
        XCTAssertTrue(second.exists)
        first.swipeLeft()
        let remove = app.buttons["Remove from Recently Watched"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        capture("Recently Watched swipe actions")
        remove.tap()
        XCTAssertTrue(first.waitForNonExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        app.swipeUp()
        XCTAssertFalse(app.buttons["play-channel-sample.idle"].exists)
        capture("Live after recent removal")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
