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
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
