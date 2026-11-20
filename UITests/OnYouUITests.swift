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
    XCTAssertFalse(app.tabBars.buttons["Scan"].exists)
    app.buttons["scan.open"].tap()
    #if !targetEnvironment(simulator)
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"].firstMatch
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    #endif
    let outcome = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == %@ OR identifier == %@", "scan.unsupported", "scan.camera.action")
    ).firstMatch
    XCTAssertTrue(outcome.waitForExistence(timeout: 15))
    XCTAssertFalse(app.textFields["scan.height"].exists)
    XCTAssertFalse(app.tabBars.firstMatch.isHittable)
    let start = app.buttons["scan.camera.action"]
    if app.descendants(matching: .any)["scan.unsupported"].exists {
      XCTAssertFalse(start.exists)
    } else {
      XCTAssertEqual(start.label, "Start scan")
      XCTAssertTrue(app.staticTexts["scan.camera.guidance"].exists)
    }
    app.buttons["scan.close"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testClosetOffersAutomaticScanWithoutMeasurementFields() {
    let app = XCUIApplication()
    app.launch()
    defer { app.terminate() }
    app.tabBars.buttons["Closet"].tap()
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Add clothes")).count, 1)
    app.buttons["closet.add.toolbar"].tap()
    XCTAssertTrue(app.navigationBars["Add clothes"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["garment.photo"].exists)
    app.buttons["garment.scan"].tap()
    XCTAssertTrue(app.navigationBars["Scan a shirt"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.textFields.count, 0)
    XCTAssertTrue(app.staticTexts["Depth capture unavailable"].exists)
    app.navigationBars["Scan a shirt"].buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Add clothes"].waitForExistence(timeout: 5))
    app.navigationBars["Add clothes"].buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Closet"].waitForExistence(timeout: 5))
  }
}
