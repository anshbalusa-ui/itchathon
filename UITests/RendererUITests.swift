import XCTest
import UIKit

final class RendererUITests: XCTestCase {
    #if DEBUG
    @MainActor
    func testRenderedGeometryRespondsToDragResetVisibilityAndMaterials() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let scene = app.descendants(matching: .any)["renderer.scene"]
        let initial = try waitForRenderedScene(app, scene: scene)
        capture(app, "R0 — generic mannequin with separate navy garment")

        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
        let end = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end)
        try expectImageChange(app, scene: scene, from: initial)
        capture(app, "R0 — actual dragged geometry")
        reveal(app.buttons["renderer.reset-view"], app: app)
        app.buttons["renderer.reset-view"].tap()
        try expectImageMatch(app, scene: scene, reference: initial)

        reveal(app.switches["renderer.garment"], app: app)
        app.switches["renderer.garment"].tap()
        let hidden = try expectImageChange(app, scene: scene, from: initial)
        XCTAssertLessThan(hidden.navyPixels, initial.navyPixels / 3, "The garment pixels, not just its label, must disappear")
        capture(app, "R0 — garment hidden, mannequin remains")
        app.switches["renderer.garment"].tap()
        try expectImageMatch(app, scene: scene, reference: initial)
        reveal(app.buttons["renderer.material.sage"], app: app)
        app.buttons["renderer.material.sage"].tap()
        let sage = try expectImageChange(app, scene: scene, from: initial)
        XCTAssertGreaterThan(sage.greenPixels, initial.greenPixels + 20)
        XCTAssertEqual(app.buttons["renderer.material.sage"].value as? String, "Selected")
        capture(app, "R0 — sage material on the actual garment")
        reveal(app.buttons["renderer.reset-appearance"], app: app)
        app.buttons["renderer.reset-appearance"].tap()
        try expectImageMatch(app, scene: scene, reference: initial)
        XCTAssertEqual(app.alerts.count, 0, "The non-AR renderer must not request camera permission")
    }

    @MainActor
    func testDismissReopenBackgroundAndOtherModuleNavigationRemainIndependent() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let scene = app.descendants(matching: .any)["renderer.scene"]
        let initial = try waitForRenderedScene(app, scene: scene)
        for _ in 0..<4 {
            reveal(app.buttons["renderer.right"], app: app)
            app.buttons["renderer.right"].tap()
            try expectImageChange(app, scene: scene, from: initial)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
            reveal(app.buttons["internal.open-renderer"], app: app)
            app.buttons["internal.open-renderer"].tap()
            XCTAssertTrue(scene.waitForExistence(timeout: 8))
            try expectImageMatch(app, scene: scene, reference: initial)
        }
        reveal(app.buttons["renderer.left"], app: app)
        app.buttons["renderer.left"].tap()
        let rotated = try expectImageChange(app, scene: scene, from: initial)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(scene.waitForExistence(timeout: 10))
        try expectImageMatch(app, scene: scene, reference: rotated)
        capture(app, "R0 — foreground recreated scene preserves view")
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["internal.open-avatar"], app: app)
        app.buttons["internal.open-avatar"].tap()
        app.buttons["Try guided capture"].tap()
        app.buttons["start-guided-scan"].tap()
        XCTAssertTrue(app.staticTexts["Camera unavailable"].waitForExistence(timeout: 5))
        app.buttons["Cancel scan"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        reveal(app.buttons["internal.open-catalog"], app: app)
        app.buttons["internal.open-catalog"].tap()
        XCTAssertTrue(app.buttons["catalog.product.sample-studio.everyday-tee"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargestTextKeepsSceneAndAlternativeControlsUsable() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app, largeText: true)
        let scene = app.descendants(matching: .any)["renderer.scene"]
        let initial = try waitForRenderedScene(app, scene: scene)
        reveal(app.buttons["renderer.right"], app: app)
        app.buttons["renderer.right"].tap()
        try expectImageChange(app, scene: scene, from: initial)
        reveal(app.buttons["renderer.reset-view"], app: app)
        app.buttons["renderer.reset-view"].tap()
        try expectImageMatch(app, scene: scene, reference: initial)
        reveal(app.switches["renderer.garment"], app: app)
        app.switches["renderer.garment"].tap()
        try expectImageChange(app, scene: scene, from: initial)
        app.switches["renderer.garment"].tap()
        reveal(app.buttons["renderer.material.stone"], app: app)
        app.buttons["renderer.material.stone"].tap()
        try expectImageChange(app, scene: scene, from: initial)
        XCTAssertEqual(app.buttons["renderer.material.stone"].value as? String, "Selected")
        capture(app, "R0 — largest text, rendered scene and selected material")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openLab(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let entry = app.buttons["internal.open-renderer"]
        reveal(entry, app: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["3D Renderer Lab"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["renderer.scene"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let controls = app.scrollViews["renderer.controls"]
        let scroll = controls.exists ? controls : app.scrollViews.firstMatch
        for _ in 0..<14 {
            if element.exists && element.isHittable { break }
            if element.exists && element.frame.midY < scroll.frame.minY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
    }

    private struct ScenePixels {
        let rgba: [UInt8]
        var navyPixels: Int {
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                if Int(rgba[index + 2]) > Int(rgba[index]) + 15 && rgba[index] < 150 { count += 1 }
            }
            return count
        }
        var greenPixels: Int {
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                let red = Int(rgba[index])
                let green = Int(rgba[index + 1])
                let blue = Int(rgba[index + 2])
                if green > red + 8 && green > blue + 5 { count += 1 }
            }
            return count
        }
        func difference(from other: Self) -> Double {
            var total = 0
            for index in rgba.indices where index % 4 != 3 {
                total += abs(Int(rgba[index]) - Int(other.rgba[index]))
            }
            return Double(total) / Double(rgba.count / 4 * 3)
        }
        func changedPixels(from other: Self) -> Int {
            var count = 0
            for index in stride(from: 0, to: rgba.count, by: 4) {
                let red = abs(Int(rgba[index]) - Int(other.rgba[index]))
                let green = abs(Int(rgba[index + 1]) - Int(other.rgba[index + 1]))
                let blue = abs(Int(rgba[index + 2]) - Int(other.rgba[index + 2]))
                if max(red, max(green, blue)) > 12 { count += 1 }
            }
            return count
        }
    }

    private enum PixelReadError: Error { case unavailableSnapshot }

    @MainActor
    private func pixels(_ app: XCUIApplication, scene: XCUIElement) throws -> ScenePixels {
        let image = app.screenshot().image
        guard let cgImage = image.cgImage else { throw PixelReadError.unavailableSnapshot }
        let scale = CGFloat(cgImage.width) / app.frame.width
        let rect = scene.frame.insetBy(dx: 4, dy: 4)
        guard rect.width > 0, rect.height > 0, app.frame.contains(rect) else {
            throw PixelReadError.unavailableSnapshot
        }
        let crop = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cropped = cgImage.cropping(to: crop) else { throw PixelReadError.unavailableSnapshot }
        var data = [UInt8](repeating: 0, count: 96 * 96 * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        try data.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 96 * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        return ScenePixels(rgba: data)
    }

    @MainActor
    private func waitForRenderedScene(_ app: XCUIApplication, scene: XCUIElement) throws -> ScenePixels {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.pixels(app, scene: scene) else { return false }
            return image.navyPixels > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rendered], timeout: 15), .completed, "Real navy mesh pixels must be visible, not just an accessibility container")
        return try pixels(app, scene: scene)
    }

    @MainActor
    @discardableResult
    private func expectImageChange(_ app: XCUIApplication, scene: XCUIElement, from reference: ScenePixels) throws -> ScenePixels {
        let change = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.pixels(app, scene: scene) else { return false }
            return image.changedPixels(from: reference) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [change], timeout: 10), .completed, "The rendered geometry/material must visibly change")
        return try pixels(app, scene: scene)
    }

    @MainActor
    private func expectImageMatch(_ app: XCUIApplication, scene: XCUIElement, reference: ScenePixels) throws {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let image = try? self.pixels(app, scene: scene) else { return false }
            return image.difference(from: reference) < 0.6
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed, "Reset/reentry must restore the known rendered view")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #else
    func testRendererLabRemainsUnavailableFromProductionLaunches() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for flags in [[], ["-fitcheck-integrated-internal"], ["-fitcheck-renderer-internal"], ["-fitcheck-avatar-internal", "-fitcheck-integrated-internal"]] {
            app.terminate()
            app.launchArguments = flags
            app.launch()
            XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["internal.open-renderer"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["renderer.scene"].exists)
        }
    }
    #endif
}
