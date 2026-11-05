import XCTest
import UIKit

final class AvatarGeometryUITests: NativeMeshUITestCase {
    #if DEBUG
    @MainActor
    func testGeneratedSurfacesRotateResetDifferAndRejectWithoutStaleGeometry() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let a = try rendered(app)
        capture(app, "S2A — actual generated synthetic surface A")
        let scene = app.descendants(matching: .any)["geometry.scene"]
        let start = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: scene.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65)))
        try changed(app, from: a)
        capture(app, "S2A — rotated generated 3D surface")
        tap("geometry.reset-view", app: app)
        try matches(app, reference: a)
        tap("geometry.fixture.surfaceB", app: app)
        try changed(app, from: a)
        capture(app, "S2A — distinct generated synthetic surface B, same material")
        for fixture in ["missingRegion", "invalidGeometry", "unverifiedSource"] {
            tap("geometry.fixture." + fixture, app: app)
            XCTAssertTrue(app.staticTexts["geometry.failure"].waitForExistence(timeout: 8))
            XCTAssertFalse(scene.exists, "Rejected input must not display the previous surface under a new label")
            XCTAssertFalse(app.staticTexts["geometry.ready"].exists)
            capture(app, "S2A — explicit synthetic rejection " + fixture)
        }
        tap("geometry.fixture.surfaceA", app: app)
        try matches(app, reference: a)
        tap("geometry.generate", app: app)
        try matches(app, reference: a)
        XCTAssertEqual(app.alerts.count, 0, "Geometry lab must not request camera permission")
        XCTAssertFalse(app.buttons["start-guided-scan"].exists)
        capture(app, "S2A — valid synthetic recovery after all rejection fixtures")
    }

    @MainActor
    func testBackgroundAndRepeatedEntryReleaseOldSurfaceAndResetSelection() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app)
        let a = try rendered(app)
        tap("geometry.fixture.surfaceB", app: app)
        let b = try changed(app, from: a)
        XCUIDevice.shared.press(.home)
        app.activate()
        try matches(app, reference: b)
        for _ in 0..<3 {
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
            tap("internal.open-geometry", app: app)
            try matches(app, reference: a)
            tap("geometry.right", app: app)
            try changed(app, from: a)
        }
        capture(app, "S2A — fresh scene after repeated navigation and foreground")
    }

    @MainActor
    func testLargestAccessibilityTextKeepsRecoveryAndRotationUsable() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app, largeText: true)
        let a = try rendered(app)
        tap("geometry.right", app: app)
        try changed(app, from: a)
        tap("geometry.reset-view", app: app)
        try matches(app, reference: a)
        tap("geometry.fixture.missingRegion", app: app)
        XCTAssertTrue(app.staticTexts["geometry.failure"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.descendants(matching: .any)["geometry.scene"].exists)
        capture(app, "S2A — accessible missing-region rejection")
        tap("geometry.fixture.surfaceB", app: app)
        try changed(app, from: a)
        tap("geometry.generate", app: app)
        _ = try rendered(app)
        capture(app, "S2A — largest accessibility text with real synthetic mesh")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
    }

    @MainActor
    func testArtifactColdRelaunchLoadsSavedBIntoRealSceneThenDeletionStaysMissing() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        let namespace = UUID().uuidString.lowercased()
        openLab(app, artifactNamespace: namespace)
        let a = try rendered(app)
        tap("geometry.artifact.save", app: app)
        artifactState("saved", app: app)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
        app.terminate()
        openLab(app, artifactNamespace: namespace)
        tap("geometry.artifact.load", app: app)
        artifactState("loaded", app: app)
        try matches(app, reference: a)
        XCTAssertEqual(app.descendants(matching: .any)["geometry.scene"].value as? String, "Disk-loaded Synthetic surface A")
        tap("geometry.right", app: app)
        try changed(app, from: a)
        tap("geometry.reset-view", app: app)
        try matches(app, reference: a)
        capture(app, "S2B — A decoded from disk after exit and true process relaunch")
        tap("geometry.fixture.surfaceB", app: app)
        let b = try changed(app, from: a)
        tap("geometry.artifact.save", app: app)
        artifactState("saved", app: app)
        capture(app, "S2B — actual synthetic B written to app-private artifact")
        tap("geometry.fixture.surfaceA", app: app)
        try matches(app, reference: a)
        tap("geometry.artifact.load", app: app)
        artifactState("loaded", app: app)
        XCTAssertTrue(app.staticTexts["geometry.artifact.loaded"].exists)
        try matches(app, reference: b)
        tap("geometry.right", app: app)
        try changed(app, from: b)
        tap("geometry.reset-view", app: app)
        try matches(app, reference: b)
        XCUIDevice.shared.press(.home)
        app.activate()
        artifactState("loaded", app: app)
        try matches(app, reference: b)

        app.terminate()
        openLab(app, artifactNamespace: namespace)
        try matches(app, reference: a)
        XCTAssertFalse(app.staticTexts["geometry.artifact.loaded"].exists)
        tap("geometry.artifact.load", app: app)
        artifactState("loaded", app: app)
        try matches(app, reference: b)
        let scene = app.descendants(matching: .any)["geometry.scene"]
        XCTAssertEqual(scene.value as? String, "Disk-loaded Synthetic surface B")
        capture(app, "S2B — B decoded from disk after true process relaunch and rendered")
        tap("geometry.artifact.delete", app: app)
        artifactState("deleted", app: app)
        XCTAssertFalse(scene.exists)
        app.terminate()
        openLab(app, artifactNamespace: namespace)
        tap("geometry.artifact.load", app: app)
        artifactState("missing", app: app)
        XCTAssertFalse(scene.exists)
        XCTAssertFalse(app.staticTexts["geometry.artifact.loaded"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        capture(app, "S2B — deleted artifact remains missing after cold relaunch")
    }

    @MainActor
    func testArtifactCorruptionAndFutureVersionPreserveFailureUntilExplicitDelete() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        for seed in ["corrupt", "future"] {
            app.terminate()
            openLab(app, artifactNamespace: UUID().uuidString.lowercased(), artifactSeed: seed)
            let a = try rendered(app)
            tap("geometry.artifact.load", app: app)
            artifactState("failed", app: app)
            XCTAssertTrue(app.staticTexts["geometry.failure"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["geometry.scene"].exists)
            XCTAssertFalse(app.staticTexts["geometry.artifact.loaded"].exists)
            capture(app, "S2B — real \(seed) file rejected without stale surface")
            tap("geometry.generate", app: app)
            try matches(app, reference: a)
            tap("geometry.artifact.save", app: app)
            artifactState("failed", app: app)
            XCTAssertTrue(app.descendants(matching: .any)["geometry.scene"].exists)
            tap("geometry.artifact.delete", app: app)
            artifactState("deleted", app: app)
            tap("geometry.generate", app: app)
            _ = try rendered(app)
            tap("geometry.artifact.save", app: app)
            artifactState("saved", app: app)
            tap("geometry.artifact.load", app: app)
            artifactState("loaded", app: app)
            try matches(app, reference: a)
            tap("geometry.artifact.delete", app: app)
            artifactState("deleted", app: app)
        }
    }

    @MainActor
    func testArtifactControlsRemainUsableAtLargestAccessibilitySize() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        openLab(app, largeText: true, artifactNamespace: UUID().uuidString.lowercased())
        let a = try rendered(app)
        tap("geometry.artifact.save", app: app)
        artifactState("saved", app: app)
        tap("geometry.artifact.load", app: app)
        artifactState("loaded", app: app)
        try matches(app, reference: a)
        tap("geometry.right", app: app)
        try changed(app, from: a)
        tap("geometry.reset-view", app: app)
        try matches(app, reference: a)
        capture(app, "S2B — largest accessibility text with actual disk-loaded synthetic mesh")
        tap("geometry.artifact.delete", app: app)
        artifactState("deleted", app: app)
        tap("geometry.artifact.load", app: app)
        artifactState("missing", app: app)
        XCTAssertFalse(app.descendants(matching: .any)["geometry.scene"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Internal Development"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func artifactState(_ value: String, app: XCUIApplication) {
        let status = app.staticTexts["geometry.artifact.status"]
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && status.value as? String == value
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed,
                       "Real artifact operation must finish in the requested state")
    }

    @MainActor
    private func openLab(_ app: XCUIApplication, largeText: Bool = false,
                         artifactNamespace: String? = nil, artifactSeed: String? = nil) {
        app.launchArguments = ["-fitcheck-integrated-internal", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if let artifactNamespace { app.launchArguments += ["-fitcheck-synthetic-artifact-test-namespace", artifactNamespace] }
        if let artifactSeed { app.launchArguments += ["-fitcheck-synthetic-artifact-test-seed", artifactSeed] }
        app.launch()
        tap("internal.open-geometry", app: app)
        XCTAssertTrue(app.navigationBars["Avatar Geometry Lab"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["geometry.scene"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func tap(_ id: String, app: XCUIApplication) {
        let element = app.buttons[id]
        let controls = app.scrollViews["geometry.controls"]
        let scroll = controls.exists ? controls : app.scrollViews.firstMatch
        for _ in 0..<45 {
            if element.exists && element.isHittable { break }
            if controls.exists {
                let scene = app.descendants(matching: .any)["geometry.scene"]
                let sceneTop = scene.exists ? scene.frame.maxY : 0
                let top = max(scroll.frame.minY, sceneTop + 12)
                let bottom = min(scroll.frame.maxY, app.frame.maxY - 20)
                let height = bottom - top
                guard height > 50 else { return XCTFail("Accessible controls need a bounded visible scroll area") }
                let midpoint = top + height / 2
                let direction: CGFloat = element.exists && element.frame.midY < midpoint ? 1 : -1
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: scroll.frame.midX - app.frame.minX, dy: midpoint - app.frame.minY))
                start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: direction * min(120, height / 3))), withVelocity: .slow, thenHoldForDuration: 0.2)
            } else {
                scroll.swipeUp()
            }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    #else
    func testGeometryLabIsAbsentFromProductionLaunches() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for flags in [[], ["-fitcheck-integrated-internal"], ["-fitcheck-geometry-internal"], ["-fitcheck-avatar-internal", "-fitcheck-integrated-internal"]] {
            app.terminate()
            app.launchArguments = flags
            app.launch()
            XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["internal.open-geometry"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["geometry.scene"].exists)
            XCTAssertFalse(app.buttons["geometry.fixture.surfaceA"].exists)
        }
    }

    func testArtifactPersistenceIsAbsentFromProductionLaunches() {
        let app = XCUIApplication()
        defer { app.terminate() }
        for flag in ["-fitcheck-integrated-internal", "-fitcheck-geometry-internal"] {
            app.terminate()
            app.launchArguments = [flag, "-fitcheck-synthetic-artifact-test-namespace", UUID().uuidString,
                                   "-fitcheck-synthetic-artifact-test-seed", "corrupt"]
            app.launch()
            XCTAssertTrue(app.staticTexts["My Body"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["geometry.artifact.save"].exists)
            XCTAssertFalse(app.buttons["geometry.artifact.load"].exists)
            XCTAssertFalse(app.buttons["geometry.artifact.delete"].exists)
            XCTAssertFalse(app.staticTexts["geometry.artifact.loaded"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["geometry.scene"].exists)
        }
    }
    #endif
}
