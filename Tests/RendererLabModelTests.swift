#if DEBUG
import MetalKit
import XCTest
@testable import FitCheck

@MainActor
final class RendererLabModelTests: XCTestCase {
    func testRepeatedOpenUsesOneSceneAndCloseReleasesOwner() throws {
        let model = RendererLabModel()
        model.open(isActive: true)
        weak var first = try XCTUnwrap(model.session)
        let id = try XCTUnwrap(first?.id)
        model.open(isActive: true)
        XCTAssertEqual(model.session?.id, id)
        XCTAssertNotNil(model.session?.view.delegate)
        model.close()
        XCTAssertNil(model.session)
        XCTAssertNil(first)
        XCTAssertEqual(model.state, .idle)
        model.setActive(true)
        XCTAssertNil(model.session, "A delayed foreground event must not reopen a dismissed viewer")
    }

    func testBackgroundReleasesSceneAndForegroundRestoresAppearanceAndOrbit() throws {
        let model = RendererLabModel()
        model.open(isActive: true)
        let firstID = try XCTUnwrap(model.session?.id)
        model.rotate(horizontal: 0.6, vertical: 0.1)
        model.selectMaterial(.sage)
        model.setGarmentVisible(false)
        let orbit = model.orbit
        weak var first = model.session
        model.setActive(false)
        XCTAssertEqual(model.state, .suspended)
        XCTAssertNil(first)
        XCTAssertNil(model.session)
        model.setActive(true)
        let restored = try XCTUnwrap(model.session)
        XCTAssertNotEqual(restored.id, firstID)
        XCTAssertEqual(model.orbit, orbit)
        XCTAssertFalse(try XCTUnwrap(restored.garment).isEnabled)
        model.setGarmentVisible(true)
        XCTAssertTrue(try XCTUnwrap(restored.garment).isEnabled)
        XCTAssertEqual(model.appearance.material, .sage)
        model.close()
    }

    func testInactiveEntryAndDismissalCannotCreateSceneFromLateRetry() {
        let model = RendererLabModel()
        model.open(isActive: false)
        XCTAssertEqual(model.state, .suspended)
        XCTAssertNil(model.session)
        model.close()
        model.retry()
        model.setActive(true)
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.session)
    }

    func testFailureRemainsExplicitAndRetryCanCreateRealScene() {
        var unavailable = true
        let model = RendererLabModel {
            if unavailable { throw RendererFailure.graphicsUnavailable }
            return try RendererSceneSession()
        }
        model.open(isActive: true)
        XCTAssertEqual(model.state, .failed(.graphicsUnavailable))
        XCTAssertNil(model.session)
        model.rotate(horizontal: 1, vertical: 1)
        XCTAssertEqual(model.orbit, .initial)
        unavailable = false
        model.retry()
        XCTAssertEqual(model.state, .ready)
        XCTAssertNotNil(model.session?.view.delegate)
        model.close()
    }

    func testMissingGarmentRecoversWithoutReplacingMannequinOrScene() throws {
        let model = RendererLabModel { try RendererSceneSession(garmentAsset: nil) }
        model.open(isActive: true)
        let scene = try XCTUnwrap(model.session)
        let mannequin = scene.mannequin
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.garmentFailure, .missingAsset)
        XCTAssertNil(scene.garment)
        model.restoreGarment()
        XCTAssertNil(model.garmentFailure)
        XCTAssertTrue(scene.mannequin === mannequin)
        XCTAssertTrue(model.session === scene)
        XCTAssertTrue(try XCTUnwrap(scene.garment).isEnabled)
        model.close()
    }

    func testResetViewAndAppearanceUpdateExistingSceneIndependently() throws {
        let model = RendererLabModel()
        model.open(isActive: true)
        let scene = try XCTUnwrap(model.session)
        model.rotate(horizontal: 1, vertical: 0.2)
        let rotated = scene.modelTransform
        model.setGarmentVisible(false)
        model.selectMaterial(.stone)
        model.resetAppearance()
        XCTAssertTrue(try XCTUnwrap(scene.garment).isEnabled)
        XCTAssertEqual(scene.modelTransform, rotated, "Appearance reset must not rotate the scene")
        model.resetView()
        XCTAssertEqual(model.orbit, .initial)
        XCTAssertNotEqual(scene.modelTransform, rotated)
        XCTAssertTrue(model.session === scene)
        model.close()
    }

    func testGpuFailureReleasesSceneAndStaleCompletionCannotAffectRetry() throws {
        let model = RendererLabModel()
        model.open(isActive: true)
        let oldScene = try XCTUnwrap(model.session)
        let oldCompletion = try XCTUnwrap(oldScene.onFailure)
        oldCompletion(.sceneCreationFailed)
        XCTAssertEqual(model.state, .failed(.sceneCreationFailed))
        XCTAssertTrue(oldScene.isDisposed)
        XCTAssertNil(model.session)
        model.retry()
        let replacement = try XCTUnwrap(model.session)
        XCTAssertNotEqual(replacement.id, oldScene.id)
        oldCompletion(.graphicsUnavailable)
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.session === replacement)
        model.close()
        replacement.onFailure?(.sceneCreationFailed)
        XCTAssertEqual(model.state, .idle)
    }
}
#endif
