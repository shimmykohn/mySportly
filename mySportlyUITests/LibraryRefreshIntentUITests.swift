import XCTest
import UIKit

@MainActor final class LibraryRefreshIntentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
    }
    func testIOS27SearchIntentHandsOffIntoNativeSearch() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--demo-intent-search"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 25))
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Sample News")
        XCTAssertTrue(app.staticTexts["search-result-count"].waitForExistence(timeout: 15))
        capture("iOS 27 search intent with real catalog results")
    }
    func testSiriOpensTVGuide() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPORTLY_TEST_SIRI"] == "1", "Opt-in device check: enable Siri and set SPORTLY_TEST_SIRI=1 in the test runner environment.")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        app.launch(); app.waitForSavedCatalog()
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.siriService.activate(voiceRecognitionText: "Open the guide in mySportly")
        let opened = app.navigationBars["Guide"].waitForExistence(timeout: 30)
        if !opened {
            capture("Siri response before guide handoff")
        }
        XCTAssertTrue(opened, "Siri did not navigate to Guide; inspect the response attachment.")
        capture("Siri opened TV Guide")
    }
    private func capture(_ name: String) {
        let item = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
