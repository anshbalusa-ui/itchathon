import XCTest

@MainActor
final class ScanCameraUITests: XCTestCase {
  func testBodyCancelExpandsInPlaceAndKeepsTheAttemptUntilConfirmed() throws {
    #if targetEnvironment(simulator)
    throw XCTSkip("Native Object Capture requires a physical iPhone.")
    #else
    let app = XCUIApplication()
    app.launchArguments = ["-onyou-tryon-fixture"]
    app.launch()
    defer { app.terminate() }
    app.buttons["scan.open"].tap()
    let start = app.buttons["scan.start"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    start.tap()
    let select = app.buttons["scan.camera.action"]
    XCTAssertTrue(select.waitForExistence(timeout: 20))
    XCTAssertTrue(select.isEnabled, "Ready-state feedback must not block Set floor.")
    XCTAssertFalse(app.staticTexts["Waiting for a depth photo"].exists)
    XCTAssertFalse(app.buttons["Turn guidance haptics off"].exists)
    app.buttons["scan.close"].tap()
    XCTAssertTrue(app.buttons["scan.cancel"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["scan.keep"].isHittable)
    XCTAssertTrue(app.buttons["scan.camera.action"].exists)
    app.buttons["scan.keep"].tap()
    XCTAssertTrue(app.buttons["scan.close"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "body-framing-and-compact-controls"
    attachment.lifetime = .keepAlways
    add(attachment)
    select.tap()
    let reframe = app.buttons["scan.reframe"]
    if reframe.waitForExistence(timeout: 5) {
      XCTAssertEqual(select.label, "Start scan")
      XCTAssertTrue(select.isEnabled)
      reframe.tap()
      XCTAssertTrue(select.waitForExistence(timeout: 5))
      XCTAssertEqual(select.label, "Set floor")
      select.tap()
      if reframe.waitForExistence(timeout: 5) {
        select.tap()
        XCTAssertTrue(app.descendants(matching: .any)["scan.capture-progress"].waitForExistence(timeout: 10))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "native-capture-started"
        capture.lifetime = .keepAlways
        add(capture)
      }
    } else {
      XCTAssertTrue(select.isEnabled)
      XCTAssertTrue(app.staticTexts["scan.camera.guidance"].label.contains("floor"))
    }
    app.buttons["scan.close"].tap()
    app.buttons["scan.cancel"].tap()
    XCTAssertTrue(app.buttons["scan.open"].waitForExistence(timeout: 10))
    #endif
  }

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
    XCTAssertTrue(app.buttons["garment.restart"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.staticTexts["Waiting for a depth photo"].exists)
    XCTAssertFalse(app.buttons["Turn guidance haptics off"].exists)
    let restart = app.buttons["garment.restart"]
    XCTAssertTrue(restart.isHittable)
    XCTAssertTrue(app.staticTexts["garment.guidance"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "physical-shirt-camera"
    attachment.lifetime = .keepAlways
    add(attachment)
    restart.tap()
    XCTAssertTrue(app.buttons["garment.restart"].waitForExistence(timeout: 10))
    app.buttons["Close scanner"].tap()
    XCTAssertTrue(app.navigationBars["Add clothes"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["garment.save"].isEnabled)
    #endif
  }
}
