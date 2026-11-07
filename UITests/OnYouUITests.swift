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
    XCTAssertFalse(app.textFields["scan.height"].exists)
    XCTAssertTrue(app.staticTexts["Automatic scale"].exists)
    app.navigationBars["Scan your body"].buttons["Cancel"].tap()
    XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testClosetOffersAutomaticScanWithoutMeasurementFields() {
    let app = XCUIApplication()
    app.launch()
    defer { app.terminate() }
    app.tabBars.buttons["Closet"].tap()
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
