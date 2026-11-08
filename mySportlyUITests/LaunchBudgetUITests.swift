import XCTest

/// Physical-device check with the normal app and its saved catalog. The app
/// makes no provider request before its first frame, so no source is touched.
@MainActor final class LaunchBudgetUITests: XCTestCase {
    func testSavedCatalogHomeIsInteractiveWithinBudget() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // The first launch after an update writes the launch snapshot; the
        // second one is the measured, everyday launch.
        app.launch()
        app.waitForSavedCatalog()
        sleep(3)
        app.terminate()
        app.launch()
        let home = app.descendants(matching: .any)["home-root"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        let value = try XCTUnwrap(home.value as? String)
        print("[LaunchBudget] home-root value: \(value)")
        let ms = try XCTUnwrap(Int(value.replacingOccurrences(of: "launch-ms=", with: "")), "Unexpected home-root value: \(value)")
        print("[LaunchBudget] first_interactive_ms=\(ms)")
        XCTAssertGreaterThan(ms, 0)
        XCTAssertLessThanOrEqual(ms, 1500)
    }
}
