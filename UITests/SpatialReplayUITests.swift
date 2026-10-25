import XCTest
import UIKit

final class SpatialReplayUITests: NativeMeshUITestCase {
    #if DEBUG
    override var viewportIdentifier: String { "replay.scene" }

    @MainActor
    func testDepthPipelineChangesActualPixelsAndRejectsMissingCalibrationAndConflicts() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let a = try rendered(app)
        XCTAssertTrue(app.staticTexts["replay.ready"].exists)
        XCTAssertTrue(app.staticTexts["replay.stages"].exists)
        capture(app, "S2C — observed depth mapped and reconstructed A, actual Metal surface")
        let scene = app.descendants(matching: .any)["replay.scene"]
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65)))
        try changed(app, from: a)
        capture(app, "S2C — rotated observation-derived open surface")
        tap("replay.reset", app: app)
        try matches(app, reference: a)
        tap("replay.case.columnB", app: app)
        try changed(app, from: a)
        XCTAssertEqual(scene.value as? String, "Replay-derived Simulated column B")
        capture(app, "S2C — different ray-cast observations produce different B geometry")
        for invalid in ["missingDepth", "badCalibration", "conflictingViews"] {
            tap("replay.case." + invalid, app: app)
            XCTAssertTrue(app.staticTexts["replay.failure"].waitForExistence(timeout: 10))
            XCTAssertFalse(scene.exists)
            XCTAssertFalse(app.staticTexts["replay.ready"].exists)
            XCTAssertFalse(app.staticTexts["replay.stages"].exists)
            capture(app, "S2C — actual " + invalid + " rejection, no stale surface")
        }
        tap("replay.case.columnA", app: app)
        try matches(app, reference: a)
        tap("replay.run", app: app)
        try matches(app, reference: a)
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.buttons["start-guided-scan"].exists)
        XCTAssertFalse(app.buttons["geometry.artifact.save"].exists)
        capture(app, "S2C — valid reconstruction recovered after rejected evidence")
    }

    @MainActor
    func testBackgroundRepeatedEntryAndRapidSwitchingKeepCurrentReplayOnly() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let a = try rendered(app)
        tap("replay.case.columnB", app: app)
        let b = try changed(app, from: a)
        XCUIDevice.shared.press(.home)
        app.activate()
        try matches(app, reference: b)
        for _ in 0..<2 {
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
            tap("internal.open-replay", app: app)
            try matches(app, reference: a)
            // No ready-state waits between these real selection events.
            tap("replay.case.columnB", app: app)
            tap("replay.case.columnA", app: app)
            tap("replay.case.columnB", app: app)
            try matches(app, reference: b)
            XCTAssertEqual(app.descendants(matching: .any)["replay.scene"].value as? String, "Replay-derived Simulated column B")
        }
        capture(app, "S2C — current B after real rapid selection, foreground and reentry")
        app.navigationBars.buttons.firstMatch.tap()
        tap("internal.open-geometry", app: app)
        XCTAssertTrue(app.navigationBars["Avatar Geometry Lab"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["geometry.scene"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["geometry.artifact.load"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["replay.scene"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testLargestAccessibilityTextRetainsRealSurfaceRecoveryAndExit() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app, largeText: true)
        let a = try rendered(app)
        tap("replay.right", app: app)
        try changed(app, from: a)
        tap("replay.reset", app: app)
        try matches(app, reference: a)
        tap("replay.case.missingDepth", app: app)
        XCTAssertTrue(app.staticTexts["replay.failure"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["replay.scene"].exists)
        revealFailureReason(app)
        capture(app, "S2C — accessible missing-depth state, no fabricated mesh")
        tap("replay.case.columnB", app: app)
        try changed(app, from: a)
        tap("replay.case.badCalibration", app: app)
        XCTAssertTrue(app.staticTexts["replay.failure"].waitForExistence(timeout: 10))
        revealFailureReason(app)
        tap("replay.case.columnA", app: app)
        try matches(app, reference: a)
        tap("replay.run", app: app)
        _ = try rendered(app)
        capture(app, "S2C — largest text with actual replay-derived Metal geometry")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    private func revealFailureReason(_ app: XCUIApplication) {
        let status = app.scrollViews["replay.status"]
        let reason = app.staticTexts["replay.failure.reason"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(reason.exists)
        for _ in 0..<24 {
            if status.frame.insetBy(dx: -1, dy: -1).contains(reason.frame) { break }
            let direction: CGFloat = reason.frame.minY < status.frame.minY ? 1 : -1
            let start = status.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05,
                        thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * 60)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(reason.isHittable, "The rejection category must be readable, not merely present in accessibility.")
        XCTAssertTrue(status.frame.insetBy(dx: -1, dy: -1).contains(reason.frame),
                      "The whole rejection reason must be scrollable into the fixed status viewport.")
    }

    @MainActor
    private func openLab(_ app: XCUIApplication, largeText: Bool = false) {
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        tap("internal.open-replay", app: app)
        XCTAssertTrue(app.navigationBars["LiDAR Reconstruction Lab"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["replay.scene"].waitForExistence(timeout: 15))
    }

    @MainActor
    private func tap(_ id: String, app: XCUIApplication) {
        let element = app.buttons[id]
        let controls = app.scrollViews["replay.controls"]
        let scroll = controls.exists ? controls : app.scrollViews.firstMatch
        for _ in 0..<45 {
            if element.exists && element.isHittable { break }
            if controls.exists {
                let scene = app.descendants(matching: .any)["replay.scene"]
                let sceneTop = scene.exists ? scene.frame.maxY : 0
                let top = max(scroll.frame.minY, sceneTop + 12)
                let bottom = min(scroll.frame.maxY, app.frame.maxY - 20)
                let height = bottom - top
                guard height > 50 else { return XCTFail("Controls require a visible bounded scroll area") }
                let midpoint = top + height / 2
                let direction: CGFloat = element.exists && element.frame.midY < midpoint ? 1 : -1
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: scroll.frame.midX - app.frame.minX, dy: midpoint - app.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * min(120, height / 3))), withVelocity: .slow, thenHoldForDuration: 0.2)
            } else { scroll.swipeUp() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
    #else
    func testSyntheticReplayIsAbsentFromEveryProductionLaunch() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for flags in [[], ["-fitcheck-integrated-internal"], ["-fitcheck-lidar-replay-internal"], ["-fitcheck-avatar-internal", "-fitcheck-integrated-internal"]] {
            app.terminate()
            app.launchArguments = flags
            app.launch()
            XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["internal.open-replay"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["replay.scene"].exists)
            XCTAssertFalse(app.buttons["replay.run"].exists)
            XCTAssertFalse(app.buttons["replay.case.columnA"].exists)
        }
    }
    #endif
}
