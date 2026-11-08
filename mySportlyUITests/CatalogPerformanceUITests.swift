import XCTest
import UIKit

/// Run explicitly on a physical device with an existing, full provider catalog.
/// Uses saved data only; never imports a source or starts playback.
@MainActor final class CatalogPerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testSavedCatalogNavigationAcrossTheApp() throws {
        let app = try openSavedCatalog()
        app.selectMainTab("Guide")
        app.selectLineup("All Channels")
        app.buttons["Guide Filters"].tap()
        let listings = app.switches["Only Channels with Listings"].firstMatch
        if listings.value as? String == "1" { listings.tap() }
        app.buttons["close-guide-options"].tap()
        defer {
            app.terminate(); app.launch(); app.selectMainTab("Guide"); app.selectLineup("My Lineup")
            app.buttons["Guide Filters"].tap()
            let listings = app.switches["Only Channels with Listings"].firstMatch
            if listings.value as? String == "0" { listings.tap() }
            app.buttons["close-guide-options"].tap()
        }
        let guideCount = app.staticTexts["guide-channel-count"].firstMatch
        let readyGuide = NSPredicate { _, _ in (Int(guideCount.value as? String ?? "0") ?? 0) > 50_000 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: readyGuide, evaluatedWith: nil)], timeout: 12), .completed)
        app.selectMainTab("My Stuff")
        var start = Date()
        app.buttons["All Channels"].firstMatch.tap()
        XCTAssertTrue(app.switches["Include Hidden Channels"].waitForExistence(timeout: 8))
        print("[CatalogPerformance] all_channels_open_seconds=\(Date().timeIntervalSince(start))")
        app.swipeUp()
        capture("Saved catalog channels and soft header", app: app)
        app.navigationBars["Channels"].buttons.element(boundBy: 0).tap()
        start = Date()
        app.buttons["Organizer"].firstMatch.tap()
        XCTAssertTrue(app.buttons["organize-groups"].waitForExistence(timeout: 8))
        print("[CatalogPerformance] organizer_controls_seconds=\(Date().timeIntervalSince(start))")
        let count = app.staticTexts["organizer-result-count"].firstMatch
        let readySuggestions = NSPredicate { _, _ in (Int(count.value as? String ?? "0") ?? 0) > 0 }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: readySuggestions, evaluatedWith: nil)], timeout: 20), .completed)
        capture("Saved catalog organizer", app: app)
        app.navigationBars["Organizer"].buttons.element(boundBy: 0).tap()
        app.buttons["Groups"].firstMatch.tap()
        app.buttons["Add Group"].tap()
        XCTAssertTrue(app.textFields["Group Name"].waitForExistence(timeout: 8))
        app.buttons["Cancel"].tap()
        app.navigationBars["Groups"].buttons.element(boundBy: 0).tap()
        app.selectMainTab("Home")
        app.buttons["home-profile"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.swipeUp()
        capture("Settings soft header", app: app)
        app.buttons["Done"].firstMatch.tap()
        app.selectMainTab("Search")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.searchFields.firstMatch.frame.midY, app.frame.midY, "Search belongs in the native header")
        capture("Native Search tab", app: app)
    }

    func testNativePlayerShowsTheFirstVideoFrame() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--demo-home-follows"]
        app.launch()
        let channel = app.buttons["home-channel-sample.0"].firstMatch
        XCTAssertTrue(channel.waitForExistence(timeout: 15))
        channel.tap()
        let preview = app.descendants(matching: .any)["stream-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "The player surface must be present during connection")
        let ready = NSPredicate { _, _ in preview.value as? String == "Video ready" }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 35), .completed)
        capture("Native player first video frame", app: app)
        app.buttons["Change Channel"].tap()
        XCTAssertTrue(app.navigationBars["Choose Channel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        app.buttons["Cancel"].tap()
        app.buttons["close-player"].tap()
        app.buttons["Stop"].firstMatch.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    private func openSavedCatalog() throws -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let loading = app.descendants(matching: .any)["catalog-loading"].firstMatch
        let ready = NSPredicate { _, _ in !loading.exists }
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: ready, evaluatedWith: nil)], timeout: 90), .completed)
        if app.buttons["Connect a Source"].firstMatch.exists { throw XCTSkip("Requires a saved provider catalog") }
        let channels = app.buttons["all-channels-link"].firstMatch
        if channels.exists, let count = channels.value as? String {
            print("[CatalogPerformance] saved_lineup=\(count)")
            if (Int(count.filter(\.isNumber)) ?? 0) < 50_000 { throw XCTSkip("Requires a large saved provider catalog") }
        }
        return app
    }

    func testSavedCatalogSearchResponseTime() throws {
        let app = try openSavedCatalog()
        app.selectMainTab("Guide")
        app.selectLineup("All Channels")
        defer { app.terminate(); app.launch(); app.selectMainTab("Guide"); app.selectLineup("My Lineup") }
        let start = Date()
        app.selectMainTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 45))
        XCTAssertLessThan(field.frame.midY, app.frame.midY, "Search belongs in the native header")
        let opening = Date().timeIntervalSince(start)
        print("[CatalogPerformance] search_open_seconds=\(opening)")
        XCTAssertLessThan(opening, 8)
        field.tap()
        let queryStart = Date()
        field.typeText("news")
        let results = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Matching Channels'")).firstMatch
        XCTAssertTrue(results.waitForExistence(timeout: 60))
        let elapsed = Date().timeIntervalSince(queryStart)
        print("[CatalogPerformance] search_results_seconds=\(elapsed)")
        XCTAssertLessThan(elapsed, 8, "Keyword search should stay responsive with the full catalog")
        field.tap()
        let broadStart = Date()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "now")
        XCTAssertTrue(results.waitForExistence(timeout: 90))
        let broadElapsed = Date().timeIntervalSince(broadStart)
        print("[CatalogPerformance] broad_search_seconds=\(broadElapsed)")
        XCTAssertLessThan(broadElapsed, 8, "Broad searches must not create every channel row at once")
        let count = app.staticTexts["search-result-count"].firstMatch
        XCTAssertGreaterThan(Int(count.value as? String ?? "0") ?? 0, 50_000, "Exercise the full saved catalog, not sample data")
        // Superseded requests must not replace the latest query's results.
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "zzzz-no-such-channel-987654")
        XCTAssertTrue(app.descendants(matching: .any)["search-empty"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(count.exists)
        print("[CatalogPerformance] latest_query_empty_state_verified=true")
    }
}
