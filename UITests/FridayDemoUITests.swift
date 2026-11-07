import XCTest
import UIKit

final class FridayDemoUITests: NativeMeshUITestCase {
    #if DEBUG
    private var activeSceneID = "demo.scene"
    override var viewportIdentifier: String { activeSceneID }

    @MainActor
    func testFridayDemoJourneyUsesRenderedGeometryAndReturnsToShowcase() throws {
        let shouldRecord = ProcessInfo.processInfo.environment["FITCHECK_RECORD_DEMO"] == "1" ||
            ProcessInfo.processInfo.environment["TEST_RUNNER_FITCHECK_RECORD_DEMO"] == "1"
        try runJourney(paced: shouldRecord)
    }

    @MainActor
    func testDebugDirectLaunchOpensActualShowcase() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-demo-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12))
        activeSceneID = "demo.scene"
        _ = try rendererRendered(app)
        tap("demo.open-avatar", app: app)
        activeSceneID = "demo.avatar.scene"
        _ = try rendered(app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].exists)
    }

    @MainActor
    func testIntegratedHubEntryAndLargestAccessibilityTextRemainUsable() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["internal.open-demo"].waitForExistence(timeout: 8))
        app.buttons["internal.open-demo"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12))
        let scene = app.descendants(matching: .any)["demo.scene"]
        let initial = try rendererRendered(app)
        XCTAssertTrue(app.buttons["demo.left"].exists)
        tap("demo.left", app: app)
        _ = try rendererChanged(app, from: initial)
        tap("demo.reset", app: app)
        try rendererMatches(app, reference: initial)
        capture(app, "largest-text showcase with rendered mannequin and reachable controls")
        tap("demo.size.medium", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Everyday Tee · Navy · M")
        tap("demo.product.weekend-tee", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Weekend Tee · Sage · M")
        _ = try rendererChanged(app, from: initial)
        tap("demo.open-avatar", app: app)
        activeSceneID = "demo.avatar.scene"
        let avatarA = try rendered(app)
        tap("demo.avatar.shape-b", app: app)
        let avatarB = try changed(app, from: avatarA)
        tap("demo.avatar.left", app: app)
        tap("demo.avatar.reset", app: app)
        try matches(app, reference: avatarB)
        capture(app, "largest-text synthetic avatar with real A/B geometry and reset")
        app.navigationBars.buttons.firstMatch.tap()
        activeSceneID = "demo.scene"
        XCTAssertTrue(scene.waitForExistence(timeout: 8))
        tap("demo.open-replay", app: app)
        activeSceneID = "demo.replay.scene"
        let replayA = try rendered(app)
        tap("demo.replay.shape-b", app: app)
        let replayB = try changed(app, from: replayA)
        tap("demo.replay.right", app: app)
        tap("demo.replay.reset", app: app)
        try matches(app, reference: replayB)
        capture(app, "largest-text simulated LiDAR geometry and reset")
        app.navigationBars.buttons.firstMatch.tap()
        activeSceneID = "demo.scene"
        XCTAssertTrue(scene.waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        XCTAssertFalse(scene.exists)
    }

    @MainActor
    private func runJourney(paced: Bool) throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        tap("internal.open-demo", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12),
                      "Integrated hub entry must open the showcase")
        activeSceneID = "demo.scene"
        let scene = app.descendants(matching: .any)["demo.scene"]
        let everyday = try rendererRendered(app)
        capture(app, "01-showcase")
        if paced { sleep(5) }

        tap("demo.right", app: app)
        _ = try rendererChanged(app, from: everyday)
        capture(app, "02-rotated-clothing")
        if paced { sleep(5) }
        tap("demo.reset", app: app)
        try rendererMatches(app, reference: everyday)
        tap("demo.garment-visible", app: app)
        let hidden = try rendererChanged(app, from: everyday)
        XCTAssertLessThan(navyPixels(hidden), navyPixels(everyday) / 3,
                          "Hiding the garment removes its actual navy mesh pixels")
        tap("demo.garment-visible", app: app)
        try rendererMatches(app, reference: everyday)

        tap("demo.size.medium", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Everyday Tee · Navy · M")
        tap("demo.product.weekend-tee", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Weekend Tee · Sage · M")
        let weekend = try rendererChanged(app, from: everyday)
        tap("demo.product.geometric-vest", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Geometric Vest Concept · Navy · M")
        _ = try rendererChanged(app, from: weekend)
        tap("demo.size.small", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Geometric Vest Concept · Navy · S")
        capture(app, "03-second-garment")
        if paced { sleep(5) }

        tap("demo.open-avatar", app: app)
        activeSceneID = "demo.avatar.scene"
        let avatarScene = app.descendants(matching: .any)[activeSceneID]
        let avatarA = try rendered(app)
        capture(app, "04-avatar-a")
        if paced { sleep(5) }
        tap("demo.avatar.shape-b", app: app)
        let avatarB = try changed(app, from: avatarA)
        XCTAssertGreaterThan(avatarB.changed(from: avatarA), 40)
        capture(app, "05-avatar-b")
        if paced { sleep(5) }
        tap("demo.avatar.shape-a", app: app)
        try matches(app, reference: avatarA)
        tap("demo.avatar.left", app: app)
        _ = try changed(app, from: avatarA)
        tap("demo.avatar.reset", app: app)
        try matches(app, reference: avatarA)
        XCTAssertTrue(avatarScene.exists)
        app.navigationBars.buttons.firstMatch.tap()
        activeSceneID = "demo.scene"
        XCTAssertTrue(scene.waitForExistence(timeout: 8))

        tap("demo.open-replay", app: app)
        activeSceneID = "demo.replay.scene"
        let replayScene = app.descendants(matching: .any)[activeSceneID]
        let replayA = try rendered(app)
        capture(app, "06-lidar-result")
        if paced { sleep(5) }
        tap("demo.replay.shape-b", app: app)
        let replayB = try changed(app, from: replayA)
        XCTAssertGreaterThan(replayB.changed(from: replayA), 40)
        capture(app, "replay-b")
        if paced { sleep(5) }
        tap("demo.replay.shape-a", app: app)
        try matches(app, reference: replayA)
        tap("demo.replay.right", app: app)
        _ = try changed(app, from: replayA)
        tap("demo.replay.reset", app: app)
        try matches(app, reference: replayA)
        XCTAssertTrue(replayScene.exists)
        app.navigationBars.buttons.firstMatch.tap()
        activeSceneID = "demo.scene"
        XCTAssertTrue(scene.waitForExistence(timeout: 8))
        capture(app, "07-return-showcase")
        if paced { sleep(5) }

        // Rapid repeated navigation must create fresh supported views, not retain stale scenes.
        for _ in 0..<2 {
            tap("demo.open-avatar", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["demo.avatar.scene"].waitForExistence(timeout: 8))
            app.navigationBars.buttons.firstMatch.tap()
            activeSceneID = "demo.scene"
            tap("demo.open-replay", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["demo.replay.scene"].waitForExistence(timeout: 8))
            app.navigationBars.buttons.firstMatch.tap()
            activeSceneID = "demo.scene"
        }
        let rotatedAfterReturn = try rendererRendered(app)
        tap("demo.left", app: app)
        let foregrounded = try rendererChanged(app, from: rotatedAfterReturn)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        try rendererMatches(app, reference: foregrounded)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        tap("internal.open-demo", app: app)
        activeSceneID = "demo.scene"
        XCTAssertTrue(scene.waitForExistence(timeout: 8))
        _ = try rendererRendered(app)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    private func tap(_ id: String, app: XCUIApplication) {
        tapElement(app.descendants(matching: .any)[id], app: app)
    }

    @MainActor
    private func tapElement(_ element: XCUIElement, app: XCUIApplication) {
        let mainControls = app.scrollViews["demo.controls"]
        let avatarControls = app.scrollViews["demo.avatar.controls"]
        let replayControls = app.scrollViews["demo.replay.controls"]
        let scroll = mainControls.exists ? mainControls :
            (avatarControls.exists ? avatarControls : (replayControls.exists ? replayControls : app.scrollViews.firstMatch))
        for _ in 0..<20 {
            if element.exists && element.isHittable { break }
            if scroll.exists {
                let startY: CGFloat = element.exists && element.frame.minY < scroll.frame.minY ? 0.3 : 0.75
                let endY: CGFloat = startY == 0.3 ? 0.75 : 0.3
                scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                    .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing demo control: \(element.identifier)")
        XCTAssertTrue(element.isHittable, "Demo control must remain reachable: \(element.identifier)")
        element.tap()
    }
    @MainActor
    private func rendererRendered(_ app: XCUIApplication) throws -> Pixels {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.scenePixels(app, id: "demo.scene") else { return false }
            return self.navyPixels(image) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed,
                       "Actual navy garment pixels must be visible in the Metal viewport")
        return try scenePixels(app, id: "demo.scene")
    }

    @MainActor
    @discardableResult
    private func rendererChanged(_ app: XCUIApplication, from reference: Pixels) throws -> Pixels {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.scenePixels(app, id: "demo.scene") else { return false }
            return image.changed(from: reference) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed,
                       "The actual mannequin/clothing pixels must visibly change")
        return try scenePixels(app, id: "demo.scene")
    }

    @MainActor
    private func rendererMatches(_ app: XCUIApplication, reference: Pixels) throws {
        let predicate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.scenePixels(app, id: "demo.scene") else { return false }
            return image.difference(from: reference) < 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [predicate], timeout: 15), .completed,
                       "Reset must restore the actual deterministic renderer pixels")
    }

    @MainActor
    private func navyPixels(_ image: Pixels) -> Int {
        var count = 0
        for index in stride(from: 0, to: image.rgba.count, by: 4) {
            if Int(image.rgba[index + 2]) > Int(image.rgba[index]) + 15 && image.rgba[index] < 150 {
                count += 1
            }
        }
        return count
    }

    @MainActor
    private func scenePixels(_ app: XCUIApplication, id: String) throws -> Pixels {
        let scene = app.descendants(matching: .any)[id]
        guard scene.exists, let image = app.screenshot().image.cgImage else {
            throw NSError(domain: "FridayDemoUITests", code: 1)
        }
        let scale = CGFloat(image.width) / app.frame.width
        let rect = scene.frame.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0, app.frame.contains(rect),
              let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                   width: rect.width * scale, height: rect.height * scale)) else {
            throw NSError(domain: "FridayDemoUITests", code: 2)
        }
        var data = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 96,
                                                   bitsPerComponent: 8, bytesPerRow: 96 * 4,
                                                   space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return Pixels(rgba: data)
    }

    #else
    func testDemoRemainsExcludedFromRelease() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for flags in [[], ["-fitcheck-demo-internal"], ["-fitcheck-integrated-internal"]] {
            app.terminate()
            app.launchArguments = flags
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["internal.open-demo"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["demo.scene"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["demo.avatar.scene"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["demo.replay.scene"].exists)
        }
    }
    #endif
}
