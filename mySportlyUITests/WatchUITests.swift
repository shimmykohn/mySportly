import XCTest
import UIKit

/// Demo mode: sample movies and a show that play Apple's public test stream.
@MainActor final class WatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testMovieResumesFromHomeAndShowListsEpisodes() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        app.tabBars.buttons["Watch"].tap()
        let movie = app.buttons["movie-sample.movie.1"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 10))
        movie.tap()
        let play = app.buttons["vod-play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["add-second-stream"].exists, "Watch Two is live-only")
        // Past the 30-second resume threshold, then minimize.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "play")], timeout: 50)
        app.buttons["close-player"].tap()
        app.tabBars.buttons["Home"].tap()
        let resume = app.buttons["home-resume"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "Home shows the movie in progress")

        app.tabBars.buttons["Watch"].tap()
        app.buttons["TV Shows"].tap()
        let show = app.buttons["show-sample.series.1"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        XCTAssertTrue(app.buttons["episode-sample.episode.1.1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["season-picker"].exists)
    }

    func testSearchFindsMoviesAndOpensWatch() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.waitForSavedCatalog()
        app.tabBars.buttons["Search"].tap()
        let tile = app.buttons["browse-watch"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("Comeback")
        XCTAssertTrue(app.descendants(matching: .any)["search-movies"].firstMatch.waitForExistence(timeout: 10))
        field.buttons["Clear text"].firstMatch.tap()
        app.buttons["Cancel"].firstMatch.tap()
        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch-root"].firstMatch.waitForExistence(timeout: 5))
    }
}
