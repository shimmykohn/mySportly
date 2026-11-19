import XCTest
import UIKit

/// Demo mode: Netflix spread over three folders, French, German and Arabic
/// titles, and Watch Later.
@MainActor final class WatchOrganizingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testServiceShelvesLanguagesAndWatchLater() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("Watch")
        XCTAssertTrue(app.descendants(matching: .any)["watch-root"].firstMatch.waitForExistence(timeout: 10))

        // Three Netflix folders are one shelf, in the user's language only.
        openShelf("Netflix", in: app)
        XCTAssertTrue(app.buttons["movie-sample.movie.5"].firstMatch.waitForExistence(timeout: 5), "English Netflix title")
        XCTAssertTrue(app.buttons["movie-sample.movie.7"].firstMatch.exists, "Untagged Netflix 4K title")
        XCTAssertFalse(app.buttons["movie-sample.movie.6"].firstMatch.exists, "French titles stay off by default")
        capture("Netflix shelf, my languages")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // All Languages brings the French copy in.
        chooseLanguage("All Languages", in: app)
        openShelf("Netflix", in: app)
        XCTAssertTrue(app.buttons["movie-sample.movie.6"].firstMatch.waitForExistence(timeout: 5), "French title with All Languages")
        capture("Netflix shelf, all languages")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        chooseLanguage("French", in: app)
        openShelf("Netflix", in: app)
        XCTAssertTrue(app.buttons["movie-sample.movie.6"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["movie-sample.movie.5"].firstMatch.exists, "Only French titles")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        chooseLanguage("My Languages", in: app)

        // Watch Later from a movie page.
        openShelf("Netflix", in: app)
        let movie = app.buttons["movie-sample.movie.5"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 5)); movie.tap()
        let later = app.buttons["vod-watch-later"].firstMatch
        XCTAssertTrue(later.waitForExistence(timeout: 5)); later.tap()
        XCTAssertTrue(app.buttons["In Watch Later"].waitForExistence(timeout: 5))
        capture("Movie saved to Watch Later")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollToTop(app)
        XCTAssertTrue(app.descendants(matching: .any)["watch-later"].firstMatch.waitForExistence(timeout: 5), "Watch Later shelf")
        capture("Watch tab with Watch Later")

        // Shows: one Netflix shelf without the Arabic show.
        app.buttons["TV Shows"].tap()
        openShelf("Netflix", in: app)
        XCTAssertTrue(app.buttons["show-sample.series.2"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["show-sample.series.3"].firstMatch.exists, "Arabic show stays off by default")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // My Stuff lists it and removes it.
        app.selectMainTab("My Stuff")
        let row = app.descendants(matching: .any)["my-stuff-later-sample.movie.5"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        capture("My Stuff with Watch Later")
        app.revealSwipeAction("Remove", on: row)
        XCTAssertFalse(row.waitForExistence(timeout: 2))
    }

    func testFollowedTeamLogosLoad() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("My Stuff")
        let team = app.buttons["my-stuff-team-New York Knicks"].firstMatch
        XCTAssertTrue(team.waitForExistence(timeout: 10))
        // ESPN's team list arrives in the background.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "logos")], timeout: 12)
        capture("My Stuff logos")
        team.tap()
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "team logo")], timeout: 4)
        capture("Team page logo")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.selectMainTab("Home")
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "home")], timeout: 3)
        capture("Home logos")
    }

    /// Opens a shelf's full list from its header, scrolling down to it.
    private func openShelf(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let header = app.buttons[title].firstMatch
        for _ in 0..<6 where !(header.exists && header.isHittable) { app.swipeUp() }
        XCTAssertTrue(header.waitForExistence(timeout: 5), "\(title) shelf", file: file, line: line)
        header.tap()
    }

    private func chooseLanguage(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        scrollToTop(app)
        app.buttons["watch-filter"].firstMatch.tap()
        let language = app.buttons["Language"].firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 5), "Language menu", file: file, line: line)
        language.tap()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), name, file: file, line: line)
        option.tap()
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
