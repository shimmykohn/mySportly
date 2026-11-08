import XCTest

/// Opt-in acceptance check that leaves the supplied source connected in the
/// normal app. Use only for a user-authorized source, with a private result bundle.
final class ProviderImportUITests: XCTestCase {
    @MainActor func testSavedSourceUsesCacheAndRefreshShowsProgress() throws {
        continueAfterFailure = false
        let input = FileManager.default.temporaryDirectory.appending(path: "mySportly-provider-sync-check.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "No authorized source refresh check was supplied.")
        defer { try? FileManager.default.removeItem(at: input) }
        let host = try JSONDecoder().decode(SyncCheck.self, from: Data(contentsOf: input)).host
        try FileManager.default.removeItem(at: input)
        let app = XCUIApplication()

        func openSources() {
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 60))
            app.buttons["Settings"].tap()
            app.buttons["Sources"].tap()
            XCTAssertTrue(app.staticTexts["source-refresh-date"].waitForExistence(timeout: 60))
        }
        let step = app.staticTexts.matching(identifier: "source-import-step").firstMatch
        app.launch()
        openSources()
        XCTAssertFalse(step.exists, "Opening a saved lineup must not start another import.")
        let savedDate = try XCTUnwrap(app.staticTexts["source-refresh-date"].value as? String)
        let description = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", host)).firstMatch
        let savedCount = Self.channelCount(description.label)
        XCTAssertGreaterThan(savedCount, 0)

        app.terminate()
        app.launch()
        openSources()
        XCTAssertFalse(step.exists)
        XCTAssertEqual(app.staticTexts["source-refresh-date"].value as? String, savedDate, "A cold launch must reuse the saved catalog.")
        XCTAssertEqual(Self.channelCount(description.label), savedCount)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(step.exists)
        XCTAssertEqual(app.staticTexts["source-refresh-date"].value as? String, savedDate, "Returning to the app must also reuse the saved catalog.")

        description.swipeLeft()
        app.buttons["Refresh"].tap()
        XCTAssertTrue(step.waitForExistence(timeout: 15))
        for title in ["Connect", "Channels", "TV Guide", "Save on This Device"] {
            XCTAssertTrue(app.staticTexts.matching(identifier: title).allElementsBoundByIndex.contains { $0.isHittable })
        }
        let guideStep = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            step.exists && step.label == "Step 3 of 4"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [guideStep], timeout: 90), .completed)
        let details = app.staticTexts.matching(identifier: "source-import-detail")
        let receivedBytes = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let detail = details.allElementsBoundByIndex.first(where: { $0.isHittable }) else { return false }
            let label = detail.label
            let received = (label.contains("downloaded") || label.contains(" of ")) && label.contains(where: \.isNumber)
            if received { print("[ProviderCheck] visibleTransfer=\(label)") }
            return received
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [receivedBytes], timeout: 30), .completed, "The guide must display actual bytes; totals are optional for chunked responses.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ipad-source-progress"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(step.waitForNonExistence(timeout: 150))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertNotEqual(app.staticTexts["source-refresh-date"].value as? String, savedDate)
        XCTAssertEqual(Self.channelCount(description.label), savedCount)
        print("[ProviderCheck] cachedLaunchStable=true foregroundStable=true refreshedChannels=\(savedCount) visualProgress=true")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.selectMainTab("Guide")
        XCTAssertTrue(app.buttons["Guide Time"].waitForExistence(timeout: 15))
        app.selectMainTab("Home")
    }

    @MainActor func testSavedSourceCatalogAndGuideCanBeBrowsed() throws {
        continueAfterFailure = false
        let input = FileManager.default.temporaryDirectory.appending(path: "mySportly-provider-sync-check.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "No authorized source sync check was supplied.")
        defer { try? FileManager.default.removeItem(at: input) }
        let host = try JSONDecoder().decode(SyncCheck.self, from: Data(contentsOf: input)).host
        try FileManager.default.removeItem(at: input)
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appending(path: "mySportly-provider-check.json"))
        let app = XCUIApplication()
        app.launch()
        if app.navigationBars["Welcome"].waitForExistence(timeout: 5) {
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 60), "The source should arrive from iCloud.")
            app.buttons["Done"].tap()
            // Retry restoration if the source arrived while setup was open.
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 60))
        app.buttons["Settings"].tap()
        app.buttons["Sources"].tap()
        let description = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", host)).firstMatch
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard description.exists else { return false }
            return Self.channelCount(description.label) > 0
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 120), .completed, "The source catalog should restore using its synced Keychain connection.")
        let count = Self.channelCount(description.label)
        print("[ProviderCheck] savedChannels=\(count)")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.selectMainTab("Guide")
        XCTAssertTrue(app.buttons["Guide Time"].waitForExistence(timeout: 15))
        app.selectMainTab("Home")
    }

    @MainActor func testAuthorizedSourceConnectsAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let input = FileManager.default.temporaryDirectory.appending(path: "mySportly-provider-check.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: input.path), "No one-use provider input was supplied.")
        defer { try? FileManager.default.removeItem(at: input) }
        let secrets = try JSONDecoder().decode(Connection.self, from: Data(contentsOf: input))
        try FileManager.default.removeItem(at: input)
        let app = XCUIApplication()
        app.launch()

        if app.navigationBars["Welcome"].waitForExistence(timeout: 15) {
            let connectSource = try XCTUnwrap(app.buttons.matching(identifier: "Connect a Source").allElementsBoundByIndex.first { $0.isHittable })
            connectSource.tap()
        } else {
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
            app.buttons["Settings"].tap()
            app.buttons["Sources"].tap()
            let host = try XCTUnwrap(URL(string: secrets.address)?.host)
            let existing = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", host))
            try XCTSkipIf(existing.count > 0, "The provider is already saved; do not create a duplicate source.")
            app.buttons["Add Source"].tap()
        }
        XCTAssertTrue(app.navigationBars["Add Source"].waitForExistence(timeout: 5))
        for (placeholder, value) in [("Name", "Live TV"), ("Server URL", secrets.address), ("Username", secrets.username)] {
            let field = app.textFields[placeholder]
            field.tap()
            field.typeText(value)
        }
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText(secrets.password + "\n")
        let connect = app.buttons["Connect and Import"]
        let form = app.collectionViews.containing(.secureTextField, identifier: "Password").firstMatch
        form.swipeUp()
        connect.tap()
        XCTAssertTrue(app.navigationBars["Welcome"].waitForNonExistence(timeout: 150), "The source should finish importing through the normal setup flow.")
        if app.navigationBars["Sources"].exists { app.buttons["Done"].tap() }
        app.waitForSavedCatalog(timeout: 30)
        XCTAssertFalse(app.alerts["Couldn’t connect"].exists)
        XCTAssertFalse(app.alerts["Guide refresh"].exists)

        app.terminate()
        app.launch()
        app.waitForSavedCatalog(timeout: 60)
        app.selectMainTab("Guide")
        XCTAssertTrue(app.buttons["Guide Time"].waitForExistence(timeout: 15))
        app.selectMainTab("Home")
    }

    private struct Connection: Decodable {
        var address: String
        var username: String
        var password: String
    }
    private struct SyncCheck: Decodable { var host: String }
    private static func channelCount(_ label: String) -> Int {
        let count = label.components(separatedBy: " channels").first ?? ""
        return Int(count.compactMap(\.wholeNumberValue).map { String($0) }.joined()) ?? 0
    }
}
