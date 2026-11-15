import XCTest
import UIKit

/// Demo mode never sends anything to OpenAI; the key here is a made-up test value and is removed at the end.
@MainActor final class OpenAISettingsUITests: XCTestCase {
    func testKeyCanBeSavedValidatedAndRemoved() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        app.waitForSavedCatalog()
        app.buttons["home-profile"].tap()
        app.buttons["openai-settings"].tap()
        let status = app.descendants(matching: .any)["openai-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        if !(status.label.contains("Not set") || (status.value as? String)?.contains("Not set") == true) {
            app.buttons["Remove Key"].tap()
        }
        let field = app.secureTextFields["openai-key-field"].firstMatch
        field.tap(); field.typeText("not-a-key")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'start with'")).firstMatch.waitForExistence(timeout: 5))
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 9) + "sk-test-0000000000000000000000")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Remove Key"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Connected"].exists || status.label.contains("Connected"))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "OpenAI settings"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Remove Key"].tap()
        XCTAssertTrue(app.buttons["Remove Key"].waitForNonExistence(timeout: 5))
    }
}
