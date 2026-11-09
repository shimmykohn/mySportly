import XCTest

extension XCUIApplication {
    @MainActor func waitForSavedCatalog(timeout: TimeInterval = 90, file: StaticString = #filePath, line: UInt = #line) {
        let ready = descendants(matching: .any).matching(NSPredicate(format: "identifier == 'home-root' AND value CONTAINS 'ready=1'")).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: timeout), "Home never reported a prepared catalog", file: file, line: line)
    }
    @MainActor func selectLineup(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let picker = buttons["lineup-scope"].firstMatch
        let filters = buttons["Guide Filters"].firstMatch
        let opensGuideFilters = !picker.exists && filters.waitForExistence(timeout: 5)
        if opensGuideFilters {
            filters.tap()
            // A sheet-dismissal animation or transient system banner can absorb
            // the tap. Verify presentation before interacting with its picker.
            if !picker.waitForExistence(timeout: 5), filters.exists && filters.isHittable { filters.tap() }
        }
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "Missing lineup filter", file: file, line: line)
        picker.tap()
        let choice = buttons.matching(NSPredicate(format: "label == %@", title))
        XCTAssertTrue(choice.firstMatch.waitForExistence(timeout: 3), file: file, line: line)
        (choice.allElementsBoundByIndex.last { $0.isHittable } ?? choice.firstMatch).tap()
        if opensGuideFilters { buttons["close-guide-options"].tap() }
    }
    /// SwiftUI exposes compact tabs as buttons and the iPad sidebar as cells.
    @MainActor func selectMainTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = buttons[title].firstMatch
        // A sheet that is still dismissing covers the tab bar for a moment.
        let hittable = NSPredicate { _, _ in button.exists && button.isHittable }
        if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: nil)], timeout: 3) == .completed {
            button.tap()
            return
        }
        let cell = cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "Missing native tab or sidebar item: \(title)", file: file, line: line)
        cell.tap()
    }
}
