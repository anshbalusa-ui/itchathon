import XCTest

@MainActor
final class ScanCameraUITests: XCTestCase {
  #if DEBUG && targetEnvironment(simulator)
  func testConsumerScanEntryCanCloseAndReopenWithoutSaving() {
    let app = XCUIApplication()
    app.launchArguments = ["-onyou-tryon-fixture"]
    app.launch()
    defer { app.terminate() }
    let body = app.descendants(matching: .any)["body.scene"]
    XCTAssertTrue(body.waitForExistence(timeout: 20))
    for attempt in 1...2 {
      let openScan = app.buttons["scan.open"]
      XCTAssertTrue(openScan.wait(for: \.isHittable, toEqual: true, timeout: 10))
      openScan.tap()
      let unavailable = app.descendants(matching: .any)["scan.unsupported"]
      XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
      XCTAssertFalse(app.buttons["scan.camera.action"].exists)
      let entry = XCTAttachment(screenshot: app.screenshot())
      entry.name = "consumer-scan-unsupported-attempt-\(attempt)"
      entry.lifetime = .keepAlways
      add(entry)
      let close = app.buttons["scan.close"]
      XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 5))
      close.tap()
      XCTAssertTrue(body.waitForExistence(timeout: 10))
      XCTAssertFalse(unavailable.exists)
    }
    let returned = XCTAttachment(screenshot: app.screenshot())
    returned.name = "consumer-body-preserved-after-scan-reentry"
    returned.lifetime = .keepAlways
    add(returned)
  }
  #endif

  func testPhysicalBodyFramingHelpAndCloseWithoutSaving() throws {
    #if targetEnvironment(simulator)
    throw XCTSkip("Live depth capture requires a physical iPhone.")
    #else
    let app = XCUIApplication()
    app.launchArguments = ["-onyou-tryon-fixture"]
    app.launch()
    defer { app.terminate() }
    app.buttons["scan.open"].tap()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"].firstMatch
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    let startScan = app.buttons["scan.camera.action"]
    XCTAssertTrue(startScan.waitForExistence(timeout: 20))
    XCTAssertEqual(startScan.label, "Start scan")
    XCTAssertTrue(app.staticTexts["scan.camera.guidance"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["scan.framing-outline"].exists)
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "body-framing-and-compact-controls"
    attachment.lifetime = .keepAlways
    add(attachment)
    app.buttons["scan.options"].tap()
    XCTAssertTrue(app.buttons["Scan help"].waitForExistence(timeout: 5))
    app.buttons["Scan help"].tap()
    let done = app.buttons["Done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5))
    let help = XCTAttachment(screenshot: app.screenshot())
    help.name = "helper-led-scan-help"
    help.lifetime = .keepAlways
    add(help)
    done.tap()
    let close = app.buttons["scan.close"]
    XCTAssertTrue(close.waitForExistence(timeout: 5))
    close.tap()
    XCTAssertTrue(app.buttons["scan.open"].wait(for: \.isHittable, toEqual: true, timeout: 10))
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
