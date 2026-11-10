import XCTest
import UIKit

final class MeasurementAvatarUITests: NativeMeshUITestCase {
    #if DEBUG
    override var viewportIdentifier: String { "measurements.scene" }

    @MainActor
    func testEditableMeasurementsChangeRenderedAnatomyAndRestoreAfterNavigation() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-demo-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        tap("demo.open-measurements", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["measurements.form"].waitForExistence(timeout: 10))
        tap("measurements.sample-a", app: app)
        capture(app, "m1-01-sample-inputs")
        tap("measurements.generate", app: app)
        let shapeA = try avatarPixels(app)
        capture(app, "m1-02-generated-a")

        tap("measurements.right", app: app)
        _ = try changedAvatar(app, from: shapeA)
        capture(app, "m1-03-rotated-human")
        tap("measurements.reset", app: app)
        try matchesAvatar(app, shapeA)
        tap("measurements.shirt", app: app)
        let clothed = try changedAvatar(app, from: shapeA)
        XCTAssertGreaterThan(clothed.navyPixels, shapeA.navyPixels + 20,
                             "The illustrative shirt must add visible clothing, not only toggle a label")
        capture(app, "m1-04-illustrative-clothing")
        tap("measurements.shirt", app: app)
        try matchesAvatar(app, shapeA)

        tap("measurements.edit", app: app)
        XCTAssertFalse(app.descendants(matching: .any)[viewportIdentifier].exists,
                       "Editing releases the previous rendered scene")
        tap("measurements.sample-b", app: app)
        tap("measurements.generate", app: app)
        let shapeB = try avatarPixels(app)
        XCTAssertGreaterThan(shapeB.silhouetteDifference(from: shapeA), 50,
                             "Different measurements must change the actual human outline")
        capture(app, "m1-05-generated-b")

        tap("measurements.edit", app: app)
        replace("measurements.waist", with: "82", app: app)
        tap("measurements.generate", app: app)
        let edited = try avatarPixels(app)
        XCTAssertGreaterThan(edited.silhouetteDifference(from: shapeB), 15,
                             "A manually typed waist must reshape the body rather than reuse the preset")
        capture(app, "m1-06-manual-waist")
        XCUIDevice.shared.press(.home)
        app.activate()
        try matchesAvatar(app, edited)
        capture(app, "m1-07-foreground-restored")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["demo.scene"].waitForExistence(timeout: 12))
        tap("demo.open-measurements", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["measurements.form"].waitForExistence(timeout: 8))
        tap("measurements.sample-a", app: app)
        tap("measurements.generate", app: app)
        try matchesAvatar(app, shapeA)
        capture(app, "m1-08-reopened-default")
    }

    @MainActor
    func testInvalidInputLargestTextAndRapidDismissalDoNotExposeStaleAvatar() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("internal.open-measurements", app: app)
        XCTAssertTrue(app.descendants(matching: .any)["measurements.form"].waitForExistence(timeout: 8))
        replace("measurements.height", with: "0", app: app)
        tap("measurements.generate", app: app)
        let validation = app.staticTexts["measurements.error"]
        XCTAssertTrue(validation.waitForExistence(timeout: 5))
        XCTAssertTrue(validation.isHittable, "Invalid input must not fail silently below the fold")
        XCTAssertTrue(app.frame.contains(validation.frame), "The complete error must remain on screen at the largest text size")
        XCTAssertFalse(app.descendants(matching: .any)[viewportIdentifier].exists,
                       "Invalid dimensions cannot leave an old successful preview visible")
        capture(app, "m1-09-invalid-input-accessibility")
        tap("measurements.sample-a", app: app)
        tap("measurements.generate", app: app)
        let reference = try avatarPixels(app)
        for id in ["measurements.left", "measurements.right", "measurements.reset", "measurements.shirt", "measurements.edit"] {
            let control = app.descendants(matching: .any)[id]
            reveal(control, app: app)
            XCTAssertTrue(control.isHittable, "The largest accessibility text must keep \(id) reachable")
        }
        tap("measurements.left", app: app)
        _ = try changedAvatar(app, from: reference)
        tap("measurements.reset", app: app)
        try matchesAvatar(app, reference)
        capture(app, "m1-10-largest-text-result")
        app.navigationBars.buttons.firstMatch.tap()

        for _ in 0..<2 {
            tap("internal.open-measurements", app: app)
            tap("measurements.generate", app: app)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertFalse(app.descendants(matching: .any)[viewportIdentifier].exists)
        }
        tap("internal.open-measurements", app: app)
        tap("measurements.generate", app: app)
        try matchesAvatar(app, reference)
        capture(app, "m1-11-rapid-navigation-recovery")
    }

    @MainActor
    private func replace(_ identifier: String, with value: String, app: XCUIApplication) {
        let field = app.textFields[identifier]
        reveal(field, app: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let previous = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The visible numeric field must actually receive keyboard focus")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        let done = app.buttons["measurements.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The decimal keyboard needs a reachable Done action")
        done.tap()
        XCTAssertEqual(field.value as? String, value, "The manually entered numeric draft must be retained")
    }

    @MainActor
    private func tap(_ identifier: String, app: XCUIApplication) {
        let toggle = app.switches[identifier]
        let element = toggle.exists ? toggle : app.descendants(matching: .any)[identifier]
        reveal(element, app: app)
        XCTAssertTrue(element.waitForExistence(timeout: 8), "Missing control: \(identifier)")
        XCTAssertTrue(element.isHittable, "Unreachable control: \(identifier)")
        if toggle.exists {
            let previous = toggle.value as? String
            XCTAssertTrue(previous == "0" || previous == "1")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", previous == "1" ? "0" : "1"), object: toggle)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        } else {
            element.tap()
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let frame = element.frame
        let preferDown = !frame.isEmpty && frame.midY > app.frame.midY
        // Offscreen SwiftUI frames are not reliable direction hints. Search
        // both ways; numeric fields also need their trailing tap point visible.
        for goDown in [preferDown, !preferDown] {
            for _ in 0..<20 {
                if element.exists && element.isHittable && element.elementType != .textField { return }
                let controls = app.scrollViews["measurements.controls"]
                let formScroll = app.scrollViews["measurements.form"]
                let formList = app.collectionViews["measurements.form"]
                let scroll = controls.exists ? controls : formScroll.exists ? formScroll : formList.exists ? formList : app.scrollViews.firstMatch
                guard scroll.exists else { return }
                var visible = scroll.frame.intersection(app.frame)
                let navigation = app.navigationBars.firstMatch
                if navigation.exists, navigation.frame.maxY > visible.minY {
                    let bottom = visible.maxY
                    visible.origin.y = navigation.frame.maxY
                    visible.size.height = max(0, bottom - visible.minY)
                }
                let actions = app.otherElements["measurements.actions"]
                let generate = app.buttons["measurements.generate"]
                if actions.exists, !actions.frame.isEmpty {
                    visible.size.height = max(0, min(visible.maxY, actions.frame.minY - 12) - visible.minY)
                } else if generate.exists && generate.isHittable {
                    visible.size.height = max(0, min(visible.maxY, generate.frame.minY - 12) - visible.minY)
                }
                guard visible.height > 60 else { return }
                if element.exists && element.isHittable && visible.contains(element.frame) { return }
                let origin = app.coordinate(withNormalizedOffset: .zero)
                // Avoid starting a drag on editable text/its selection gesture.
                let x = visible.maxX - 18 - app.frame.minX
                let startY = visible.minY + visible.height * (goDown ? 0.78 : 0.25) - app.frame.minY
                let endY = visible.minY + visible.height * (goDown ? 0.25 : 0.78) - app.frame.minY
                origin.withOffset(CGVector(dx: x, dy: startY))
                    .press(forDuration: 0.15, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)))
            }
        }
        let diagnostic = XCTAttachment(string: "Unreachable element: \(element.debugDescription)\n\(app.debugDescription)")
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
    }

    private enum PixelFailure: Error { case unavailable }

    @MainActor
    private func readAvatar(_ app: XCUIApplication) throws -> Pixels {
        let scene = app.descendants(matching: .any)[viewportIdentifier]
        guard scene.exists, let image = app.screenshot().image.cgImage else { throw PixelFailure.unavailable }
        let rect = scene.frame.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0, app.frame.contains(rect) else { throw PixelFailure.unavailable }
        let scale = CGFloat(image.width) / app.frame.width
        let cropRect = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let crop = image.cropping(to: cropRect) else { throw PixelFailure.unavailable }
        var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 96, bitsPerComponent: 8,
                                                 bytesPerRow: 96 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return Pixels(rgba: bytes)
    }

    @MainActor
    private func avatarPixels(_ app: XCUIApplication) throws -> Pixels {
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let pixels = try? self.readAvatar(app) else { return false }
            return pixels.bodyPixels > 180
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 25), .completed,
                       "A real anatomical Metal surface must be visibly rendered")
        return try readAvatar(app)
    }

    @MainActor
    private func changedAvatar(_ app: XCUIApplication, from reference: Pixels) throws -> Pixels {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let pixels = try? self.readAvatar(app) else { return false }
            return pixels.bodyPixels > 180 && pixels.changed(from: reference) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 15), .completed)
        return try readAvatar(app)
    }

    @MainActor
    private func matchesAvatar(_ app: XCUIApplication, _ reference: Pixels) throws {
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let pixels = try? self.readAvatar(app) else { return false }
            return pixels.bodyPixels > 180 && pixels.difference(from: reference) < 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 20), .completed,
                       "Reset, foreground and reopening must restore the actual deterministic mesh")
    }
    #else
    func testMeasurementDemoIsExcludedFromRelease() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for arguments in [[], ["-fitcheck-demo-internal"], ["-fitcheck-integrated-internal"]] {
            app.terminate()
            app.launchArguments = arguments
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["body.scene"].waitForExistence(timeout: 8))
            for id in ["demo.open-measurements", "internal.open-measurements", "measurements.form", "measurements.scene"] {
                XCTAssertFalse(app.descendants(matching: .any)[id].exists)
            }
        }
    }
    #endif
}

#if DEBUG
private extension NativeMeshUITestCase.Pixels {
    func isBody(_ index: Int) -> Bool {
        let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
        return max(r, max(g, b)) < 220 && max(r, max(g, b)) > 25
    }
    var bodyPixels: Int {
        var count = 0
        for index in stride(from: 0, to: rgba.count, by: 4) where isBody(index) { count += 1 }
        return count
    }
    var navyPixels: Int {
        var count = 0
        for index in stride(from: 0, to: rgba.count, by: 4) {
            let r = Int(rgba[index]), g = Int(rgba[index + 1]), b = Int(rgba[index + 2])
            if b > r + 15 && b > g + 4 && b < 220 { count += 1 }
        }
        return count
    }
    func silhouetteDifference(from other: Self) -> Int {
        var count = 0
        for index in stride(from: 0, to: rgba.count, by: 4) where isBody(index) != other.isBody(index) { count += 1 }
        return count
    }
}
#endif
