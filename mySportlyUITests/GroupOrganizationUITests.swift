import XCTest
import UIKit

@MainActor final class GroupOrganizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testEmptyFavoritesAndRefreshHaveNoExtraActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-empty-favorites", "--demo-refresh-check"]
        app.launch(); app.waitForSavedCatalog()
        XCTAssertTrue(app.activityIndicators["live-loading"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["source-import-step"].exists)
        XCTAssertFalse(app.staticTexts["Preparing your lineup…"].exists)
        XCTAssertFalse(app.buttons["Cancel Import"].exists)
        XCTAssertFalse(app.staticTexts["Favorites Today"].exists)
        XCTAssertFalse(app.staticTexts["No broadcasts listed for your favorites today."].exists)
        capture("Refresh spinner in soft header")
    }
    func testGroupOrganizerAndDynamicCategories() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-sport-groups"]
        app.launch(); app.waitForSavedCatalog()
        let organizer = app.buttons["Organize Channels"].firstMatch
        for _ in 0..<8 where !organizer.isHittable { app.swipeUp() }
        XCTAssertTrue(organizer.waitForExistence(timeout: 8)); organizer.tap()
        XCTAssertTrue(app.buttons["organize-groups"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["AI Service"].exists)
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Golf\n")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "organizer-group-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let path = app.textFields["group-path"]
        XCTAssertTrue(path.waitForExistence(timeout: 8)); path.tap()
        let text = path.value as? String ?? ""
        path.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count) + "Learning / Astronomy\n")
        app.buttons["save-group-path"].tap()
        capture("Saved dynamic category path")
        app.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Organizer"].waitForExistence(timeout: 8))
        app.buttons["BackButton"].firstMatch.tap()
        let category = app.buttons["category-group-Learning"].firstMatch
        for _ in 0..<6 where !category.isHittable { app.swipeUp() }
        XCTAssertTrue(category.waitForExistence(timeout: 8)); category.tap()
        let astronomy = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Astronomy")).firstMatch
        XCTAssertTrue(astronomy.waitForExistence(timeout: 8)); astronomy.tap()
        XCTAssertTrue(app.buttons["play-channel-sample.golf.1"].waitForExistence(timeout: 8))
        capture("New category and subcategory in browsing")
    }
    func testRepeatedSportsVisitsShowPreparedResults() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--demo-sport-groups"]
        app.launch(); app.waitForSavedCatalog()
        app.selectMainTab("Sports")
        XCTAssertTrue(app.buttons["manage-sports-following"].waitForExistence(timeout: 8))
        let browse = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Browse by Sport")).firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 8))
        for _ in 0..<3 {
            app.selectMainTab("Live"); app.selectMainTab("Sports")
            XCTAssertTrue(browse.exists)
            XCTAssertFalse(app.staticTexts["Finding sports…"].exists)
        }
        capture("Repeated Sports visit")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
