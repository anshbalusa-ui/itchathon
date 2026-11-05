import XCTest
import UIKit

final class HumanAvatarShowcaseUITests: NativeMeshUITestCase {
    #if DEBUG
    private var activeSceneID = "demo.scene"
    override var viewportIdentifier: String { activeSceneID }

    @MainActor
    func testHumanShowcasePixelsRegionsFitMapProductsAndRecovery() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-demo-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12),
                      "The direct Debug demo route opens the actual human showcase")
        let fullBody = try waitForViewportPixels(app)
        capture(app, "human-01-fullbody")
        XCTAssertTrue(app.descendants(matching: .any)["demo.garment-visible"].exists)

        tap("demo.garment-visible", app: app)
        let garmentOff = try changedPixels(app, from: fullBody)
        XCTAssertLessThan(garmentOff.blueGarmentPixels, fullBody.blueGarmentPixels,
                          "Hiding clothing must remove its rendered garment pixels")
        tap("demo.garment-visible", app: app)
        try pixelMatch(app, fullBody)
        capture(app, "human-02-clothing")

        let sampleText = app.staticTexts["demo.fit-disclaimer"]
        XCTAssertTrue(sampleText.waitForExistence(timeout: 5), "Fit visualization must be identified as sample-only")
        let disclaimer = sampleText.label.lowercased()
        XCTAssertTrue(disclaimer.contains("sample") || disclaimer.contains("illustrative"),
                      "Copy must identify the visualization as a sample/illustration")
        XCTAssertTrue(disclaimer.contains("not") || disclaimer.contains("doesn't") || disclaimer.contains("does not"),
                      "Copy must explicitly avoid representing verified personal fit")

        tap("demo.fit-map", app: app)
        let mapped = try changedPixels(app, from: fullBody)
        XCTAssertGreaterThan(mapped.redAmberPixels, 8,
                             "The sample clearance map shows visible warm-color garment regions")
        XCTAssertGreaterThan(mapped.roomGreenPixels, 8,
                             "The sample clearance map shows visible green garment regions")
        capture(app, "human-03-fit-map")
        tap("demo.fit-map", app: app)
        try pixelMatch(app, fullBody)

        tap("demo.region.chest", app: app)
        let chest = try changedPixels(app, from: fullBody)
        capture(app, "human-04-chest-focus")
        tap("demo.region.waist", app: app)
        let waist = try changedPixels(app, from: chest)
        capture(app, "human-05-waist-focus")
        tap("demo.region.shoulders", app: app)
        let shoulders = try changedPixels(app, from: waist)
        tap("demo.region.hips", app: app)
        let hips = try changedPixels(app, from: shoulders)
        tap("demo.region.arms", app: app)
        let arms = try changedPixels(app, from: hips)
        tap("demo.region.legs", app: app)
        _ = try changedPixels(app, from: arms)

        tap("demo.region.whole", app: app)
        try pixelMatch(app, fullBody)
        tap("demo.left", app: app)
        _ = try changedPixels(app, from: fullBody)
        tap("demo.reset", app: app)
        try pixelMatch(app, fullBody)
        XCTAssertTrue(app.staticTexts["demo.region-summary"].label.lowercased().contains("whole"),
                      "Whole/reset clears any focused body region")
        tap("demo.size.medium", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Everyday Tee · Navy · M")
        try pixelMatch(app, fullBody)

        tap("demo.product.weekend-tee", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Weekend Tee · Sage · M")
        let sage = try changedPixels(app, from: fullBody)
        XCTAssertGreaterThan(sage.greenClothingPixels, 8,
                             "Sage selection changes the actual garment surface, not only its title")
        capture(app, "human-06-sage")
        XCTAssertTrue(app.staticTexts["demo.region-summary"].label.lowercased().contains("whole"),
                      "Changing products clears stale body-region focus")

        tap("demo.product.geometric-vest", app: app)
        XCTAssertEqual(app.staticTexts["demo.product-context"].label, "Geometric Vest Concept · Navy · M")
        let vest = try changedPixels(app, from: sage)
        XCTAssertGreaterThan(vest.blueGarmentPixels, 8,
                             "Vest selection renders its own garment surface")
        capture(app, "human-07-vest")
        XCTAssertTrue(app.staticTexts["demo.region-summary"].label.lowercased().contains("whole"))

        tap("demo.fit-map", app: app)
        let mappedVest = try changedPixels(app, from: vest)
        tap("demo.region.chest", app: app)
        let mappedChest = try changedPixels(app, from: mappedVest)
        XCTAssertTrue(app.staticTexts["demo.region-summary"].label.contains("Chest"))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 10))
        try pixelMatch(app, mappedChest)

        tap("demo.open-avatar", app: app)
        activeSceneID = "demo.avatar.scene"
        XCTAssertTrue(app.descendants(matching: .any)[activeSceneID].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        activeSceneID = "demo.scene"
        XCTAssertTrue(app.descendants(matching: .any)[activeSceneID].waitForExistence(timeout: 8))
        try pixelMatch(app, mappedChest)
        XCTAssertTrue(app.staticTexts["demo.region-summary"].label.contains("Chest"),
                      "Pushing and popping another demo chapter preserves the selected region")
        XCTAssertTrue(app.descendants(matching: .any)["demo.fit-map"].exists)
    }

    @MainActor
    func testHumanShowcaseLargestAccessibilityControlsAndExitRemainReachable() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                              "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("internal.open-demo", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12))
        _ = try waitForViewportPixels(app)
        for identifier in ["demo.fit-map", "demo.region.chest", "demo.region.waist", "demo.region.arms",
                           "demo.region.legs", "demo.region.whole", "demo.reset", "demo.open-avatar"] {
            let control = app.descendants(matching: .any)[identifier]
            makeHittable(control, app: app)
            XCTAssertTrue(control.isHittable, "Largest accessibility text keeps \(identifier) reachable")
        }
        tap("demo.region.chest", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 8),
                      "The showcase remains exit-navigable at the largest accessibility size")
    }

    @MainActor
    private func tap(_ identifier: String, app: XCUIApplication) {
        let toggle = app.switches[identifier]
        let isToggle = toggle.exists
        let element = isToggle ? toggle : app.descendants(matching: .any)[identifier]
        makeHittable(element, app: app)
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing showcase control: \(identifier)")
        XCTAssertTrue(element.isHittable, "Showcase control must be reachable: \(identifier)")
        if isToggle {
            guard let previous = toggle.value as? String, previous == "0" || previous == "1" else {
                return XCTFail("The native switch must expose its actual on/off state")
            }
            // SwiftUI exposes the whole labelled row as a switch. Hit the
            // native track, not a label/row-center accessibility hit point.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", previous == "1" ? "0" : "1"), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed,
                           "The actual native switch must change before checking rendered pixels")
        } else {
            element.tap()
        }
    }

    @MainActor
    private func makeHittable(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews["demo.controls"]
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            if !scroll.exists {
                if element.exists && element.frame.maxY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
                continue
            }
            let startY: CGFloat = element.exists && element.frame.minY < scroll.frame.minY ? 0.25 : 0.78
            let endY: CGFloat = startY == 0.25 ? 0.78 : 0.25
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY)))
        }
    }

    @MainActor
    private func waitForViewportPixels(_ app: XCUIApplication) throws -> Pixels {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.viewportPixels(app) else { return false }
            return image.nonBackgroundPixels > 80 && image.blueGarmentPixels > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       "The human body and clothing must render actual viewport pixels")
        return try viewportPixels(app)
    }

    @MainActor
    private func changedPixels(_ app: XCUIApplication, from reference: Pixels) throws -> Pixels {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.viewportPixels(app) else { return false }
            return image.changed(from: reference) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       "The actual body/clothing viewport pixels must change")
        return try viewportPixels(app)
    }

    @MainActor
    private func pixelMatch(_ app: XCUIApplication, _ reference: Pixels) throws {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.viewportPixels(app) else { return false }
            return image.difference(from: reference) < 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       "Reset/toggle/navigation restores the deterministic rendered view")
    }

    @MainActor
    private func viewportPixels(_ app: XCUIApplication) throws -> Pixels {
        let scene = app.descendants(matching: .any)[viewportIdentifier]
        guard scene.exists, let image = app.screenshot().image.cgImage else {
            throw NSError(domain: "HumanAvatarShowcaseUITests", code: 1)
        }
        let scale = CGFloat(image.width) / app.frame.width
        let rect = scene.frame.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0, app.frame.contains(rect),
              let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale,
                                                    width: rect.width * scale, height: rect.height * scale)) else {
            throw NSError(domain: "HumanAvatarShowcaseUITests", code: 2)
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
    #endif
}

#if DEBUG
private extension NativeMeshUITestCase.Pixels {
    var nonBackgroundPixels: Int {
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
            if max(r, max(g, b)) - min(r, min(g, b)) > 12 || max(r, max(g, b)) < 235 { count += 1 }
        }
        return count
    }
    var blueGarmentPixels: Int {
        countPixels { r, g, b in b > r + 15 && b > g + 4 && b < 220 }
    }
    var greenClothingPixels: Int {
        countPixels { r, g, b in g > r + 10 && g > b + 3 && g > 45 && g < 235 }
    }
    var redAmberPixels: Int {
        countPixels { r, g, b in r > 75 && r > g + 18 && (g > b + 3 || r > 145) }
    }
    var roomGreenPixels: Int {
        countPixels { r, g, b in g > 65 && g > r + 15 && g > b + 8 }
    }
    private func countPixels(where predicate: (Int, Int, Int) -> Bool) -> Int {
        var count = 0
        for i in stride(from: 0, to: rgba.count, by: 4) {
            if predicate(Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2])) { count += 1 }
        }
        return count
    }
}
#endif
