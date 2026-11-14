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
  func testManualMeasurementsChangeRenderedBodyWithoutAuthorizingScanTryOn() throws {
    app.launchArguments = ["-onyou-tryon-fixture", "-onyou-fixture-scenario=missing-avatar",
      "-on-you.measurement-unit", "centimeters", "-on-you.wireframe", "NO",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
    app.launch()
    XCTAssertTrue(scene("onyou.synthetic").waitForExistence(timeout: 30))
    let example = try bodyPixels()
    capture("integration-01-example-body-largest-text")

    XCTAssertGreaterThanOrEqual(app.buttons["body.measurements"].frame.height, 44)
    tap("body.measurements")
    XCTAssertTrue(app.buttons["measurement.cancel"].waitForExistence(timeout: 10))
    let originalWaist = replaceMeasurement("measurement.waist", with: "125")
    capture("integration-01b-measurements-editor")
    tap("measurement.cancel")
    XCTAssertLessThan(try bodyPixels().difference(from: example), 0.01, "Leaving without Save must preserve the original rendered body")
    tap("body.measurements")
    XCTAssertTrue(app.buttons["measurement.cancel"].waitForExistence(timeout: 10))
    XCTAssertEqual(replaceMeasurement("measurement.waist", with: "125"), originalWaist, "Cancelled input must not become the next editor draft")
    tap("measurement.save")
    _ = try bodyPixels(changedFrom: example)
    capture("integration-02-saved-measurement-body-largest-text")

    app.tabBars.buttons["History"].tap()
    let saved = app.cells.firstMatch
    XCTAssertTrue(saved.waitForExistence(timeout: 10))
    saved.tap()
    let recordedWaist = scene("snapshot.waist")
    reveal(recordedWaist)
    XCTAssertTrue(recordedWaist.exists)
    XCTAssertTrue((recordedWaist.value as? String ?? "").contains("125"), "History must contain the entered measurement")
    capture("integration-03-measurement-history")

    app.tabBars.buttons["Body"].tap()
    _ = try bodyPixels(changedFrom: example)
    openShirt("Fixture · Tide shirt")
    reveal(app.buttons["garment.scanbody"])
    XCTAssertTrue(app.buttons["garment.scanbody"].isHittable)
    XCTAssertFalse(app.buttons["garment.tryon"].exists, "Manual measurements must not authorize a captured-avatar try-on")
    XCTAssertFalse(scene("tryon.scene").exists)
    capture("integration-04-manual-model-keeps-scan-required")
  }
  func testMeasuredBodySizeJourneyChangesNormalSceneAndRestoresDeterministically() throws {
    app.launchArguments = ["-onyou-tryon-fixture", "-onyou-fixture-scenario=missing-avatar",
      "-on-you.measurement-unit", "centimeters", "-on-you.wireframe", "NO",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL", "-AppleInterfaceStyle", "Light"]
    app.launch()
    XCTAssertTrue(scene("onyou.synthetic").waitForExistence(timeout: 30))
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 20))
    XCTAssertTrue(try bodyPixels().hasVisibleBody, "The normal Body scene must contain a rendered mannequin")
    capture("measurement-journey-example-front-full-screen")
    captureScene("measurement-journey-example-front-scene-only")

    tap("body.measurements")
    waitForMeasurementEditor()
    let fields = ["height", "chest", "waist", "hips", "shoulders"]
    var original: [String: String] = [:]
    for field in fields {
      let input = app.textFields["measurement.\(field)"]
      reveal(input)
      XCTAssertTrue(input.waitForExistence(timeout: 10))
      original[field] = input.value as? String
    }
    XCTAssertEqual(original.count, fields.count, "Every original measurement must be retained for restoration")
    tap("measurement.cancel")
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 10))
    let example = try bodyPixels()

    let slim = ["height": "175", "chest": "86", "waist": "68", "hips": "92", "shoulders": "40"]
    let broad = ["height": "175", "chest": "116", "waist": "108", "hips": "120", "shoulders": "49"]
    let tall = ["height": "205", "chest": "104", "waist": "88", "hips": "108", "shoulders": "45"]
    let slimPixels = try saveMeasurements(slim, fields: fields, changedFrom: example)
    capture("measurement-journey-slim-front-full-screen")
    captureScene("measurement-journey-slim-front-scene-only")
    XCTAssertGreaterThan(slimPixels.difference(from: example), 0.015, "A saved slim measurement set must change actual mannequin pixels")

    let broadPixels = try saveMeasurements(broad, fields: fields, changedFrom: slimPixels)
    capture("measurement-journey-broad-front-full-screen")
    captureScene("measurement-journey-broad-front-scene-only")
    XCTAssertGreaterThan(broadPixels.difference(from: slimPixels), 0.015,
      "Same-height slim and broad inputs must produce different front-view renders")
    XCTAssertGreaterThan(broadPixels.difference(from: example), 0.015)

    let tallPixels = try saveMeasurements(tall, fields: fields, changedFrom: broadPixels)
    capture("measurement-journey-tall-front-full-screen")
    captureScene("measurement-journey-tall-front-scene-only")
    XCTAssertGreaterThan(tallPixels.difference(from: broadPixels), 0.015,
      "A taller measurement set must produce a distinct actual render")

    dragBodyScene()
    let orbitPixels = try bodyPixels()
    XCTAssertGreaterThan(orbitPixels.difference(from: tallPixels), 0.01,
      "Dragging the normal Body scene must change the camera view")
    capture("measurement-journey-tall-orbit-side-full-screen")
    captureScene("measurement-journey-tall-orbit-side-scene-only")

    dragBodyScene(reverse: true)
    let returnedFront = try bodyPixels()
    XCTAssertGreaterThan(returnedFront.difference(from: orbitPixels), 0.01,
      "A reverse drag must return to the front view")
    let restored = try saveMeasurements(original, fields: fields, changedFrom: tallPixels)
    capture("measurement-journey-restored-front-full-screen")
    captureScene("measurement-journey-restored-front-scene-only")
    XCTAssertLessThan(restored.difference(from: example), 0.01,
      "Restoring the original measurements must deterministically restore the original render")
  }

  private func saveMeasurements(_ values: [String: String], fields: [String],
                               changedFrom previous: Pixels) throws -> Pixels {
    tap("body.measurements")
    waitForMeasurementEditor()
    for field in fields {
      guard let value = values[field] else { XCTFail("Missing measurement: \(field)"); continue }
      _ = replaceMeasurement("measurement.\(field)", with: value)
    }
    tap("measurement.save")
    XCTAssertTrue(scene("body.scene").waitForExistence(timeout: 10), "Saving measurements must return to the normal Body scene")
    return try bodyPixels(changedFrom: previous)
  }

  private func waitForMeasurementEditor() {
    XCTAssertTrue(app.buttons["measurement.cancel"].waitForExistence(timeout: 10))
    let form = app.collectionViews["measurement.form"]
    let height = app.textFields["measurement.height"]
    var previousFrame = CGRect.null
    let settled = NSPredicate { [self] _, _ in
      guard form.exists, height.exists else { return false }
      let frame = height.frame
      defer { previousFrame = frame }
      return !frame.isEmpty && form.frame.intersection(app.frame).contains(frame) && frame == previousFrame
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: app)], timeout: 10),
      .completed, "Wait for the sheet's native measurement row to finish laying out before typing")
  }

  private func dragBodyScene(reverse: Bool = false) {
    let viewport = scene("body.scene")
    XCTAssertTrue(viewport.waitForExistence(timeout: 10))
    let start = CGVector(dx: reverse ? 0.78 : 0.22, dy: 0.5)
    let end = CGVector(dx: reverse ? 0.22 : 0.78, dy: 0.5)
    viewport.coordinate(withNormalizedOffset: start).press(forDuration: 0.1,
      thenDragTo: viewport.coordinate(withNormalizedOffset: end), withVelocity: .slow, thenHoldForDuration: 0.1)
  }

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
    reveal(title)
    XCTAssertTrue(title.waitForExistence(timeout: 10))
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
    if !app.navigationBars.buttons.matching(identifier: identifier).firstMatch.exists { reveal(button) }
    XCTAssertTrue(button.waitForExistence(timeout: 10), identifier)
    XCTAssertTrue(button.isHittable, identifier)
    button.tap()
  }

  private func reveal(_ element: XCUIElement) {
    let form = app.collectionViews["measurement.form"]
    if form.exists {
      // Native Form rows are lazy; asking for an absent row's frame throws.
      let frame = element.exists ? element.frame : .zero
      let preferDown = frame.isEmpty || frame.midY >= form.frame.midY
      for down in [preferDown, !preferDown] {
        for _ in 0..<12 {
          // A presenting sheet can expose a row before it has an activation
          // frame. Check layout before asking AX for a hit point.
          if element.exists {
            let frame = element.frame
            if !frame.isEmpty && form.frame.intersection(app.frame).contains(frame) && element.isHittable { return }
          }
          form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.8 : 0.2))
            .press(forDuration: 0.15, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: down ? 0.2 : 0.8)))
        }
      }
      let diagnostic = XCTAttachment(string: "Unreachable native measurement control: \(element.debugDescription)\n\(app.debugDescription)")
      diagnostic.lifetime = .keepAlways
      add(diagnostic)
      capture("unreachable-native-measurement-control")
      return
    }
    let bodyControls = app.scrollViews["body.controls"]
    if bodyControls.exists && bodyControls.isHittable {
      var visible = bodyControls.frame.intersection(app.frame)
      let tabs = app.tabBars.firstMatch
      if tabs.exists { visible.size.height = max(0, min(visible.maxY, tabs.frame.minY) - visible.minY) }
      for _ in 0..<12 {
        if element.exists && element.isHittable && visible.contains(element.frame) { return }
        let down = !element.exists || element.frame.isEmpty || element.frame.maxY > visible.maxY
        // Short, slow swipes keep tall actions in view without touching the indicator or tab bar.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = visible.midX - app.frame.minX
        let from = visible.midY + visible.height * (down ? 0.1 : -0.1) - app.frame.minY
        let to = visible.midY + visible.height * (down ? -0.1 : 0.1) - app.frame.minY
        origin.withOffset(CGVector(dx: x, dy: from)).press(forDuration: 0.15,
          thenDragTo: origin.withOffset(CGVector(dx: x, dy: to)),
          withVelocity: .slow, thenHoldForDuration: 0.15)
      }
      capture("unreachable-body-control")
      return
    }
    for _ in 0..<8 {
      if element.exists && element.isHittable { return }
      let controls = app.scrollViews["tryon.controls"]
      let list = app.collectionViews.firstMatch
      if controls.exists {
        let below = !element.exists || element.frame.midY >= controls.frame.midY
        let from = CGVector(dx: 0.92, dy: below ? 0.85 : 0.2)
        let to = CGVector(dx: 0.92, dy: below ? 0.2 : 0.85)
        controls.coordinate(withNormalizedOffset: from)
          .press(forDuration: 0.05, thenDragTo: controls.coordinate(withNormalizedOffset: to))
      } else if list.exists {
        // Scroll the list gutter; dragging its interactive 3D preview orbits the model.
        let below = !element.exists || element.frame.midY >= list.frame.midY
        let from = CGVector(dx: 0.98, dy: below ? 0.75 : 0.25)
        let to = CGVector(dx: 0.98, dy: below ? 0.25 : 0.75)
        list.coordinate(withNormalizedOffset: from).press(forDuration: 0.15,
          thenDragTo: list.coordinate(withNormalizedOffset: to),
          withVelocity: .slow, thenHoldForDuration: 0.15)
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

  private func bodyPixels(changedFrom previous: Pixels? = nil) throws -> Pixels {
    var latest: Pixels?
    let ready = NSPredicate { [self] _, _ in
      let viewport = scene("body.scene")
      guard viewport.exists, (viewport.value as? String) != "Updating body model",
            let image = try? Pixels(image: viewport.screenshot().image), image.hasVisibleBody else { return false }
      latest = image
      return previous.map { image.difference(from: $0) > 0.015 } ?? true
    }
    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: app)], timeout: 25),
      .completed, "The actual body surface must be visible and change when the saved measurement changes")
    return try XCTUnwrap(latest)
  }

  private func replaceMeasurement(_ identifier: String, with value: String) -> String {
    let field = app.textFields[identifier]
    reveal(field)
    XCTAssertTrue(field.isHittable)
    let previous = field.value as? String ?? ""
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
    app.buttons["Done"].tap()
    XCTAssertEqual(field.value as? String, value)
    return previous
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  private func captureScene(_ name: String) {
    let viewport = scene("body.scene")
    XCTAssertTrue(viewport.exists, "The normal Body scene must be available for scene-only evidence")
    let attachment = XCTAttachment(screenshot: viewport.screenshot())
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
    var hasVisibleBody: Bool {
      var count = 0
      for y in 15..<145 {
        for x in 25..<95 {
          let i = (y * 120 + x) * 4
          let contrast = abs(Int(rgba[i])-Int(rgba[0])) + abs(Int(rgba[i+1])-Int(rgba[1])) + abs(Int(rgba[i+2])-Int(rgba[2]))
          if contrast > 45 { count += 1 }
          if count > 200 { return true }
        }
      }
      return false
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
