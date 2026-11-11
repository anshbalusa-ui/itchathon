import XCTest

@MainActor
final class ScanCameraUITests: XCTestCase {
  func testPhysicalShirtCameraShowsGuidanceAndCanRestartWithoutSaving() throws {
    #if targetEnvironment(simulator)
    throw XCTSkip("Live LiDAR camera check requires a physical iPhone.")
    #else
    let app = XCUIApplication()
    app.launchArguments = ["-onyou-tryon-fixture"]
    app.launch()
    defer { app.terminate() }
    app.tabBars.buttons["Closet"].tap()
    app.buttons["closet.add.toolbar"].tap()
    XCTAssertTrue(app.buttons["garment.scan"].waitForExistence(timeout: 10))
    app.buttons["garment.scan"].tap()
    let start = app.buttons["garment.start"]
    guard start.waitForExistence(timeout: 10) else { throw XCTSkip("LiDAR capture unavailable on this device.") }
    addUIInterruptionMonitor(withDescription: "Camera access") { alert in
      if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
      return false
    }
    start.tap()
    let position = app.descendants(matching: .any)["scan.position"]
    XCTAssertTrue(position.waitForExistence(timeout: 15))
    let restart = app.buttons["garment.restart"]
    XCTAssertTrue(restart.isHittable)
    XCTAssertTrue(app.staticTexts["garment.guidance"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "physical-shirt-camera"
    attachment.lifetime = .keepAlways
    add(attachment)
    restart.tap()
    XCTAssertTrue(position.waitForExistence(timeout: 10))
    app.buttons["Close scanner"].tap()
    XCTAssertTrue(app.navigationBars["Add clothes"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["garment.save"].isEnabled)
    #endif
  }
}
