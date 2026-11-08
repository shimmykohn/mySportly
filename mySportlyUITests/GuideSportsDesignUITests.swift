import XCTest
import UIKit

@MainActor final class GuideSportsDesignUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testSavedGuideOpensWithListingsAndFiltersAreSeparate() {
        let app = XCUIApplication()
        app.launch()
        waitForCatalog(app)
        app.selectMainTab("Guide")
        let count = app.staticTexts["guide-channel-count"].firstMatch
        let ready = NSPredicate { _, _ in (Int(count.value as? String ?? "0") ?? 0) > 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 30), .completed)
        XCTAssertFalse(app.switches["Only Channels with Listings"].exists)
        capture("After - Saved Guide")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'guide-channel-'")).firstMatch
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(app.buttons["Watch Channel"].waitForExistence(timeout: 5))
        capture("After - Channel Schedule")
        app.buttons["BackButton"].firstMatch.tap()
        app.buttons["Guide Filters"].tap()
        XCTAssertTrue(app.switches["Only Channels with Listings"].waitForExistence(timeout: 5))
        capture("After - Guide Filters")
        app.buttons["close-guide-options"].tap()
    }
    func testUnifiedLibraryKeepsTeamsInsideLeagueAndHomeShowsTheGameOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check"]
        app.launch(); waitForCatalog(app)
        app.selectMainTab("My Stuff")
        app.buttons["add-to-library"].tap()
        app.buttons["Teams & Leagues"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("NBA")
        app.buttons["Add NBA to Library"].tap()
        XCTAssertTrue(app.buttons["Remove NBA from Library"].waitForExistence(timeout: 5))
        search.typeText("\n")
        back(app, expecting: app.buttons["Teams & Leagues"])
        back(app, expecting: app.buttons["library-item-NBA"])
        XCTAssertFalse(app.buttons["library-item-New York Knicks"].exists, "A league is saved as one Library item")
        app.buttons["library-item-NBA"].tap()
        XCTAssertEqual(app.switches["sports-favorite"].value as? String, "0")
        setFavorite(app, to: true)
        let teams = app.buttons["league-teams"]
        XCTAssertTrue(teams.waitForExistence(timeout: 5)); teams.tap()
        let teamSearch = app.searchFields.firstMatch
        teamSearch.tap(); teamSearch.typeText("Knicks")
        teamSearch.typeText("\n")
        app.buttons["sports-item-New York Knicks"].tap()
        XCTAssertTrue(app.buttons["save-sports-item"].waitForExistence(timeout: 5))
        app.buttons["save-sports-item"].tap()
        XCTAssertEqual(app.switches["sports-favorite"].value as? String, "0", "A league favorite must not favorite all its teams")
        setFavorite(app, to: true)
        capture("Unified Library - separately saved team and favorite")
        app.selectMainTab("Home")
        let games = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-game-'"))
        XCTAssertTrue(app.descendants(matching: .any)["home-teams"].waitForExistence(timeout: 10))
        XCTAssertTrue(games.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(games.count, 1, "A followed team's game in an added league must appear once, in Your Teams")
        capture("Home - one game for a team in an added league")
        app.selectMainTab("My Stuff")
        back(app, expecting: app.navigationBars["NBA Teams"])
        back(app, expecting: app.buttons["league-teams"])
        app.buttons["Library Options"].tap()
        app.buttons["Remove from Library"].tap()
        XCTAssertTrue(app.buttons["save-sports-item"].exists)
        back(app, expecting: app.buttons["library-item-New York Knicks"])
        XCTAssertFalse(app.buttons["library-item-NBA"].exists)
        capture("Unified Library - individually saved team retained")
        let team = app.buttons["library-item-New York Knicks"]
        XCTAssertTrue(team.waitForExistence(timeout: 5)); team.tap()
        XCTAssertTrue(app.staticTexts["In Your Library"].exists)
        XCTAssertEqual(app.switches["sports-favorite"].value as? String, "1", "Removing a league preserves an individually favorited team")
        setFavorite(app, to: false)
        XCTAssertTrue(app.staticTexts["In Your Library"].exists)
        app.selectMainTab("Home")
        XCTAssertTrue(app.buttons["home-game-sample.game"].waitForExistence(timeout: 10), "A saved team stays on Home without a star")
    }
    private func back(_ app: XCUIApplication, expecting destination: XCUIElement) {
        // Notification banners can absorb toolbar taps on a personal device.
        // Dismiss just the transient banner, then verify navigation actually ran.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)["NotificationShortLookView"].firstMatch
        if banner.exists { banner.swipeUp() }
        let back = app.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let previousLabel = back.label
        back.tap()
        if !destination.waitForExistence(timeout: 5), back.exists && back.label == previousLabel {
            if banner.exists { banner.swipeUp() }
            back.tap()
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
    }
    private func waitForCatalog(_ app: XCUIApplication) {
        let loading = app.descendants(matching: .any)["catalog-loading"].firstMatch
        app.waitForSavedCatalog()
        let ready = NSPredicate { _, _ in !loading.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 60), .completed)
    }
    private func setFavorite(_ app: XCUIApplication, to value: Bool) {
        let row = app.switches["sports-favorite"]
        // SwiftUI exposes the whole labeled row as a switch on iPad. Tap
        // its trailing control instead of the empty center of that row.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let changed = NSPredicate { _, _ in row.value as? String == (value ? "1" : "0") }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: nil)], timeout: 5), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
