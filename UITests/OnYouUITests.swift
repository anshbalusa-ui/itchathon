import XCTest

final class OnYouUITests: XCTestCase {
  @MainActor
  func testCleanViewerAndScanSetup() {
    let app = XCUIApplication()
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.navigationBars["On You"].exists)
    XCTAssertFalse(app.buttons["Full screen"].exists)
    XCTAssertFalse(app.buttons["Edit measurements"].exists)
    XCTAssertFalse(app.segmentedControls.buttons["Front"].exists)
    app.tabBars.buttons["Scan"].tap()
    app.buttons["scan.open"].tap()
    XCTAssertTrue(app.navigationBars["Scan your body"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.textFields["scan.height"].exists)
    app.navigationBars.buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testMeasurementsUpdateBodyAndHistory() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    defer { app.terminate() }
    XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.descendants(matching: .any)["body.scene"].exists)
    app.tabBars.buttons["Measurements"].tap()
    let height = app.textFields["measurement.height"]
    XCTAssertTrue(height.waitForExistence(timeout: 5))
    height.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
    height.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "185")
    XCTAssertEqual(height.value as? String, "185")
    app.toolbars.buttons["Done"].tap()
    app.swipeUp()
    XCTAssertTrue(app.buttons["measurement.save"].isEnabled)
    app.buttons["measurement.save"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Your body"].exists)
    app.tabBars.buttons["History"].tap()
    XCTAssertFalse(app.staticTexts["No measurements yet"].exists)
    app.cells.containing(.staticText, identifier: "Chest 96 · Waist 80 · Hips 98 cm").firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Saved body"].waitForExistence(timeout: 5))
    let savedHeight = app.descendants(matching: .any)["snapshot.height"]
    XCTAssertTrue(savedHeight.waitForExistence(timeout: 5))
    XCTAssertEqual(savedHeight.value as? String, "185 cm")
  }
}
