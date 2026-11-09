import XCTest
import UIKit

@MainActor
final class TryOnUITests: XCTestCase {
  private var app: XCUIApplication!
  private enum Cloth { case tide, coral }
  private var firstVisibleStarted: TimeInterval?

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    app = XCUIApplication()
  }

  #if DEBUG
  func testSavedAvatarClosetTryOnRotationVisibilityAndReopening() throws {
    launchFixture()
    capture("01-body-saved-synthetic-avatar")
    app.tabBars.buttons["Closet"].tap()
    XCTAssertTrue(app.staticTexts["Fixture · Tide shirt"].waitForExistence(timeout: 10))
    capture("02a-closet-selection")
    openShirt("Fixture · Tide shirt", selectCloset: false)
    capture("02-closet-selected-shirt")
    tryOn()
    let front = try rendered(.tide)
    capture("03-shirt-front")
    tap("tryon.right")
    let quarter = try rendered(.tide)
    XCTAssertGreaterThan(front.difference(from: quarter), 0.01, "Rotation must change rendered geometry, not only controls")
    capture("04-shirt-three-quarter")
    tap("tryon.right")
    let side = try rendered(.tide)
    XCTAssertGreaterThan(quarter.difference(from: side), 0.01)
    capture("05-shirt-side")
    tap("tryon.back")
    _ = try rendered(.tide)
    capture("06-shirt-back")
    tap("tryon.front")
    _ = try rendered(.tide)
    let toggle = app.switches["tryon.shirt"]
    XCTAssertTrue(toggle.isHittable)
    toggle.tap()
    let hidden = try pixels()
    XCTAssertLessThan(hidden.count(.tide), front.count(.tide) / 6, "The actual shirt pixels must disappear")
    capture("07-shirt-hidden")
    toggle.tap()
    _ = try rendered(.tide)
    capture("08-shirt-restored")
    tap("tryon.left")
    _ = try rendered(.tide)
    tap("tryon.reset")
    let reset = try rendered(.tide)
    XCTAssertLessThan(front.difference(from: reset), 0.035, "Reset must restore the actual camera")
    tap("tryon.close")
    XCTAssertTrue(app.buttons["garment.tryon"].waitForExistence(timeout: 10))
    tryOn()
    _ = try rendered(.tide)
    capture("09-shirt-reopened")
    tap("tryon.close")
    app.tabBars.buttons["Body"].tap()
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 10))
    capture("10-clean-return-to-body")
    tap("scan.open")
    XCTAssertTrue(app.navigationBars["Scan your body"].waitForExistence(timeout: 10))
    XCTAssertTrue(scene("scan.journey").exists)
    XCTAssertFalse(app.buttons["scan.start"].isEnabled, "Simulator guidance must not invent camera capture support")
    capture("17-body-scan-introduction")
    tap("scan.close")
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 10))
    capture("18-return-after-scan-introduction")
  }

  func testRapidDismissalNewGarmentAndBackgroundDoNotResurrectOldScene() throws {
    launchFixture()
    openShirt("Fixture · Tide shirt")
    for _ in 0..<3 {
      tryOn(waitForScene: false)
      tap("tryon.close")
      XCTAssertTrue(app.buttons["garment.tryon"].waitForExistence(timeout: 10))
    }
    app.navigationBars.buttons.element(boundBy: 0).tap()
    openShirt("Fixture · Coral shirt", selectCloset: false)
    tryOn()
    let coral = try rendered(.coral)
    XCTAssertLessThan(coral.count(.tide), coral.count(.coral) / 5)
    capture("11-second-garment")
    XCUIDevice.shared.press(.home)
    app.activate()
    _ = try rendered(.coral)
    tap("tryon.close")
    tryOn()
    let reopened = try rendered(.coral)
    XCTAssertLessThan(reopened.count(.tide), reopened.count(.coral) / 5)
  }

  func testDistinctBodyAndLargestAccessibilityControlsRemainUsable() throws {
    launchFixture(body: "b", accessibility: true)
    openShirt("Fixture · Coral shirt")
    tryOn()
    _ = try rendered(.coral)
    capture("12-second-body-accessibility")
    for identifier in ["tryon.left", "tryon.reset", "tryon.right", "tryon.front", "tryon.back"] {
      reveal(app.buttons[identifier])
      let button = app.buttons[identifier]
      XCTAssertTrue(button.isHittable, identifier)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44, identifier)
      button.tap()
      _ = try rendered(.coral)
    }
    reveal(app.switches["tryon.shirt"])
    app.switches["tryon.shirt"].tap()
    XCTAssertLessThan(try pixels().count(.coral), 30)
    app.switches["tryon.shirt"].tap()
    _ = try rendered(.coral)
    tap("tryon.close")
    XCTAssertTrue(app.buttons["garment.tryon"].waitForExistence(timeout: 10))
  }

  func testPrerequisitesRejectWithRecoveryAndNeverShowSuccessfulBareAvatar() throws {
    launchFixture(scenario: "missing-avatar")
    openShirt("Fixture · Tide shirt")
    reveal(app.buttons["garment.scanbody"])
    XCTAssertTrue(app.buttons["garment.scanbody"].isHittable)
    XCTAssertFalse(app.buttons["garment.tryon"].exists)
    capture("13-missing-avatar-action")

    app.terminate()
    launchFixture(scenario: "photo-only")
    openShirt("Fixture · Tide shirt")
    reveal(app.buttons["garment.rescan"])
    XCTAssertTrue(app.buttons["garment.rescan"].isHittable)
    XCTAssertFalse(app.buttons["garment.tryon"].exists)
    capture("14-photo-without-scale-action")

    app.terminate()
    launchFixture(scenario: "missing-photo")
    openShirt("Fixture · Tide shirt")
    XCTAssertTrue(scene("garment.photo-missing").waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["garment.tryon"].exists)
    reveal(app.buttons["garment.rescan"])
    XCTAssertTrue(app.buttons["garment.rescan"].isHittable)
    XCTAssertFalse(scene("tryon.scene").exists)
    capture("15-missing-photo-recovery")

    app.terminate()
    launchFixture(scenario: "unusable-pose")
    openShirt("Fixture · Tide shirt")
    tryOn(waitForScene: false)
    XCTAssertTrue(app.buttons["tryon.retry"].waitForExistence(timeout: 40))
    XCTAssertFalse(scene("tryon.scene").exists, "A bare avatar must not be a successful try-on")
    capture("16-unusable-pose-recovery")
    tap("tryon.retry")
    XCTAssertTrue(app.buttons["tryon.retry"].waitForExistence(timeout: 40))
    tap("tryon.back-to-garment")
    XCTAssertTrue(app.buttons["garment.tryon"].waitForExistence(timeout: 10))
  }
  #else
  func testSyntheticFixtureRouteIsExcludedFromRelease() {
    app.launchArguments = ["-onyou-tryon-fixture", "-onyou-fixture-body=b", "-onyou-fixture-scenario=unusable-pose"]
    app.launch()
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 20))
    XCTAssertFalse(scene("onyou.synthetic").exists)
    app.tabBars.buttons["Closet"].tap()
    XCTAssertTrue(app.buttons["closet.add.toolbar"].exists)
    XCTAssertFalse(app.staticTexts["Fixture · Tide shirt"].exists)
    XCTAssertFalse(app.staticTexts["Fixture · Coral shirt"].exists)
    XCTAssertFalse(scene("tryon.scene").exists)
  }
  #endif

  private func launchFixture(body: String = "a", scenario: String = "valid", accessibility: Bool = false) {
    app.launchArguments = ["-onyou-tryon-fixture", "-onyou-fixture-body=\(body)", "-onyou-fixture-scenario=\(scenario)"]
    if accessibility {
      app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
    }
    app.launch()
    XCTAssertTrue(scene("onyou.synthetic").waitForExistence(timeout: 30))
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 20))
  }

  private func openShirt(_ name: String, selectCloset: Bool = true) {
    if selectCloset { app.tabBars.buttons["Closet"].tap() }
    let title = app.staticTexts[name]
    XCTAssertTrue(title.waitForExistence(timeout: 10))
    reveal(title)
    title.tap()
  }

  private func tryOn(waitForScene: Bool = true) {
    reveal(app.buttons["garment.tryon"])
    XCTAssertTrue(app.buttons["garment.tryon"].isHittable)
    firstVisibleStarted = ProcessInfo.processInfo.systemUptime
    app.buttons["garment.tryon"].tap()
    if waitForScene { XCTAssertTrue(scene("tryon.scene").waitForExistence(timeout: 60)) }
  }

  private func scene(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func tap(_ identifier: String) {
    let button = app.buttons[identifier]
    XCTAssertTrue(button.waitForExistence(timeout: 10), identifier)
    reveal(button)
    XCTAssertTrue(button.isHittable, identifier)
    button.tap()
  }

  private func reveal(_ element: XCUIElement) {
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      let controls = app.scrollViews["tryon.controls"]
      if controls.exists {
        let below = !element.exists || element.frame.midY >= controls.frame.midY
        let from = CGVector(dx: 0.92, dy: below ? 0.85 : 0.2)
        let to = CGVector(dx: 0.92, dy: below ? 0.2 : 0.85)
        controls.coordinate(withNormalizedOffset: from)
          .press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: to))
      } else {
        // A full fling can skip a tall Dynamic Type action row on compact
        // screens. Move a short distance in either direction toward its frame.
        let below = !element.exists || element.frame.midY >= app.frame.midY
        let from = CGVector(dx: 0.92,dy: below ? 0.72 : 0.48)
        let to = CGVector(dx: 0.92,dy: below ? 0.50 : 0.70)
        app.coordinate(withNormalizedOffset: from)
          .press(forDuration: 0.05,thenDragTo: app.coordinate(withNormalizedOffset: to))
      }
    }
  }

  private func rendered(_ cloth: Cloth) throws -> Pixels {
    var latest: Pixels?
    let ready = NSPredicate { [self] _, _ in
      guard scene("tryon.scene").exists, let image = try? pixels() else { return false }
      latest = image
      return image.count(cloth) > 100
    }
    let expectation = XCTNSPredicateExpectation(predicate: ready, object: app)
    XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 25), .completed, "The actual rendered shirt must be visible")
    if let started = firstVisibleStarted {
      let timing = XCTAttachment(string: "tap_to_first_observed_shirt_pixels_ms=\((ProcessInfo.processInfo.systemUptime-started)*1000); includes XCTest interaction/screenshot overhead")
      timing.name = "first-visible-shirt-pixels"
      timing.lifetime = .keepAlways
      add(timing)
      firstVisibleStarted = nil
    }
    return try XCTUnwrap(latest)
  }

  private func pixels() throws -> Pixels {
    try Pixels(image: scene("tryon.scene").screenshot().image)
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private struct Pixels {
    let rgba: [UInt8]
    init(image: UIImage) throws {
      let cg = try XCTUnwrap(image.cgImage)
      var bytes = [UInt8](repeating: 0, count: 120 * 180 * 4)
      try bytes.withUnsafeMutableBytes { buffer in
        let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 120, height: 180,
          bitsPerComponent: 8, bytesPerRow: 120 * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 120, height: 180))
      }
      rgba = bytes
    }
    func count(_ cloth: Cloth) -> Int {
      var count = 0
      for i in stride(from: 0, to: rgba.count, by: 4) {
        let r = Int(rgba[i]), g = Int(rgba[i+1]), b = Int(rgba[i+2])
        switch cloth {
        case .tide: if g > r + 25 && b > r + 20 && g > 45 { count += 1 }
        case .coral: if r > 60 && r > g * 16 / 10 && r > b * 14 / 10 { count += 1 }
        }
      }
      return count
    }
    func difference(from other: Self) -> Double {
      var changed = 0
      for i in stride(from: 0, to: rgba.count, by: 4) {
        let delta = abs(Int(rgba[i])-Int(other.rgba[i])) + abs(Int(rgba[i+1])-Int(other.rgba[i+1])) + abs(Int(rgba[i+2])-Int(other.rgba[i+2]))
        if delta > 35 { changed += 1 }
      }
      return Double(changed) / Double(120 * 180)
    }
  }
}
