import XCTest
import UIKit

/// Opt-in, sequential two-device acceptance. The driver supplies a unique group
/// name and write/read/delete/absent phase in the test runner's environment.
/// This exercises the app's real private SwiftData store through native controls.
final class CloudSyncUITests: XCTestCase {
    @MainActor func testPersonalGroupSync() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["MYSPORTLY_SYNC_PHASE"] ?? ""
        let name = environment["MYSPORTLY_SYNC_NAME"] ?? ""
        try XCTSkipUnless(["write", "read", "delete", "absent"].contains(phase) && name.hasPrefix("Sync check "), "Run only as part of the explicit two-device sync check.")
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = XCUIApplication()
        app.launch()
        if app.navigationBars["Welcome"].waitForExistence(timeout: 5) { app.buttons["Explore Sample Catalog"].tap() }
        app.selectMainTab("My Stuff")
        app.buttons["Groups"].tap()
        let group = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        switch phase {
        case "write":
            XCTAssertFalse(group.exists)
            app.buttons["Add Group"].tap()
            app.textFields["Group Name"].tap()
            app.textFields["Group Name"].typeText(name)
            app.buttons["Save"].tap()
            XCTAssertTrue(group.waitForExistence(timeout: 10))
        case "read":
            XCTAssertTrue(group.waitForExistence(timeout: 90), "The group written on the other device did not arrive.")
        case "delete":
            XCTAssertTrue(group.waitForExistence(timeout: 90))
            group.swipeLeft()
            app.buttons["Delete"].firstMatch.tap()
            XCTAssertTrue(group.waitForNonExistence(timeout: 10))
        case "absent":
            XCTAssertTrue(group.waitForNonExistence(timeout: 90), "The other device's deletion did not arrive.")
        default: XCTFail("Unsupported sync phase")
        }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "iCloud group \(phase)"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
