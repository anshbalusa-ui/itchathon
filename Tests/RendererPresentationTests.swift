#if DEBUG
import MetalKit
import XCTest
@testable import FitCheck

@MainActor
final class RendererPresentationTests: XCTestCase {
    private let sagePresentation = RendererPresentation(
        navigationTitle: "Illustrative 3D Preview",
        context: "Sample Tee · Sage · Small",
        initialMaterial: .sage,
        allowsMaterialChanges: false
    )

    func testSageInitialMaterialRendersAndResetRestoresSageWithoutResettingView() throws {
        let model = RendererLabModel(presentation: sagePresentation)
        model.open(isActive: true)
        let scene = try XCTUnwrap(model.session)
        let garment = try XCTUnwrap(scene.garment)
        XCTAssertEqual(model.appearance.material, .sage)
        XCTAssertEqual(garment.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))

        model.rotate(horizontal: 0.7, vertical: 0.2)
        let rotated = scene.modelTransform
        model.setGarmentVisible(false)
        XCTAssertFalse(garment.isEnabled)
        model.resetAppearance()
        XCTAssertTrue(garment.isEnabled)
        XCTAssertEqual(model.appearance.material, .sage)
        XCTAssertEqual(garment.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        XCTAssertEqual(scene.modelTransform, rotated, "Appearance reset must not reset the view")

        model.resetView()
        XCTAssertEqual(model.orbit, .initial)
        XCTAssertNotEqual(scene.modelTransform, rotated)
        XCTAssertEqual(garment.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        model.close()
        XCTAssertTrue(scene.isDisposed)
        XCTAssertNil(model.session)
    }

    func testSagePresentationRejectsMaterialChanges() throws {
        let model = RendererLabModel(presentation: sagePresentation)
        model.open(isActive: true)
        let garment = try XCTUnwrap(model.session?.garment)

        model.selectMaterial(.stone)
        XCTAssertEqual(model.appearance.material, .sage)
        XCTAssertEqual(garment.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        model.selectMaterial(.navy)
        XCTAssertEqual(model.appearance.material, .sage)
        XCTAssertEqual(garment.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        model.close()
    }

    func testBackgroundRecreationAndRetryPreserveSageAppearance() throws {
        let model = RendererLabModel(presentation: sagePresentation)
        model.open(isActive: true)
        let original = try XCTUnwrap(model.session)
        model.setGarmentVisible(false)
        model.setActive(false)
        XCTAssertTrue(original.isDisposed)
        XCTAssertNil(model.session)

        model.setActive(true)
        let foreground = try XCTUnwrap(model.session)
        XCTAssertNotEqual(foreground.id, original.id)
        XCTAssertFalse(try XCTUnwrap(foreground.garment).isEnabled)
        XCTAssertEqual(foreground.garment?.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        let staleCompletion = try XCTUnwrap(foreground.onFailure)
        staleCompletion(.sceneCreationFailed)
        XCTAssertTrue(foreground.isDisposed)
        model.retry()
        let retried = try XCTUnwrap(model.session)
        XCTAssertNotEqual(retried.id, foreground.id)
        XCTAssertFalse(try XCTUnwrap(retried.garment).isEnabled)
        XCTAssertEqual(retried.garment?.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        staleCompletion(.graphicsUnavailable)
        XCTAssertTrue(model.session === retried)
        model.close()
        XCTAssertTrue(retried.isDisposed)
    }
}
#endif
