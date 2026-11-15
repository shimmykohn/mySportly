import XCTest
import UIKit

@MainActor final class SearchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testBrowseAndGroupedResults() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sports-api-check", "--demo-home-follows"]
        app.launch()
        app.waitForSavedCatalog()
        app.selectMainTab("Search")
        for tile in ["Sports", "News", "Movies", "Kids", "NBA", "Basketball"] {
            XCTAssertTrue(app.buttons["browse-\(tile)"].waitForExistence(timeout: 5), "Missing tile \(tile)")
        }
        XCTAssertFalse(app.staticTexts["Try a Search"].exists)
        XCTAssertFalse(app.buttons["Ask Apple Intelligence"].exists)
        capture("Search before typing")
        app.buttons["browse-News"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'play-channel-'")).firstMatch.waitForExistence(timeout: 10))
        capture("Browse News")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let field = app.searchFields.firstMatch
        field.tap(); field.typeText("knicks")
        let teams = app.descendants(matching: .any)["search-teams"].firstMatch
        XCTAssertTrue(teams.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New York Knicks'")).firstMatch.exists)
        capture("Search teams")
        field.typeText(XCUIKeyboardKey.delete.rawValue.repeated(6) + "news\n")
        let groups = NSPredicate { _, _ in
            app.descendants(matching: .any)["search-live"].exists || app.descendants(matching: .any)["search-channels"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: groups, evaluatedWith: nil)], timeout: 10), .completed)
        capture("Search grouped results")
        field.buttons["Clear text"].firstMatch.tap()
        XCTAssertTrue(app.buttons["search-recent-news"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private extension String {
    func repeated(_ count: Int) -> String { String(repeating: self, count: count) }
}
