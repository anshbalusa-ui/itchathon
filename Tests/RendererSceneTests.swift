#if DEBUG
import Metal
import MetalKit
import simd
import XCTest
@testable import FitCheck

@MainActor
final class RendererSceneTests: XCTestCase {
    func testSceneCreatesIndexedGPUObjectsAndOnDemandView() throws {
        let scene = try RendererSceneSession()
        XCTAssertFalse(scene.mannequin.mesh.vertices.isEmpty)
        XCTAssertFalse(scene.mannequin.mesh.indices.isEmpty)
        XCTAssertNotNil(scene.mannequin.vertexBuffer)
        XCTAssertNotNil(scene.mannequin.indexBuffer)
        XCTAssertNotNil(scene.garment?.vertexBuffer)
        XCTAssertNotNil(scene.garment?.indexBuffer)
        XCTAssertNotNil(scene.pipelineState)
        XCTAssertTrue(scene.view.enableSetNeedsDisplay)
        XCTAssertTrue(scene.view.isPaused)
        XCTAssertTrue(finite(scene.viewProjection))
        XCTAssertTrue(finite(scene.modelTransform))
        let bounds = scene.mannequin.mesh
        XCTAssertGreaterThan(bounds.maximum.y - bounds.minimum.y, 1.7)
        XCTAssertLessThan(bounds.maximum.y - bounds.minimum.y, 1.9)
        XCTAssertLessThan(abs(bounds.minimum.y), 0.02)
        scene.dispose()
    }

    func testAppearanceUpdatesDrawObjectButRetainsGPUBuffers() throws {
        let scene = try RendererSceneSession()
        let garment = try XCTUnwrap(scene.garment)
        let vertexBuffer = try XCTUnwrap(garment.vertexBuffer)
        let indexBuffer = try XCTUnwrap(garment.indexBuffer)
        let mannequinBuffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
        var appearance = RendererAppearance()
        scene.apply(orbit: .initial, appearance: appearance)
        let navy = garment.color
        appearance.material = .sage
        appearance.garmentVisible = false
        scene.apply(orbit: .initial, appearance: appearance)
        XCTAssertFalse(garment.isEnabled)
        XCTAssertNotEqual(garment.color, navy)
        XCTAssertTrue(scene.mannequin.isEnabled)
        XCTAssertTrue(vertexBuffer === garment.vertexBuffer)
        XCTAssertTrue(indexBuffer === garment.indexBuffer)
        XCTAssertTrue(mannequinBuffer === scene.mannequin.vertexBuffer)
        appearance.reset()
        scene.apply(orbit: .initial, appearance: appearance)
        XCTAssertEqual(garment.color, navy)
        XCTAssertTrue(garment.isEnabled)
        scene.dispose()
    }

    func testOrbitResetIsDeterministicAndCameraFitsAllowedRotation() throws {
        let scene = try RendererSceneSession()
        scene.apply(orbit: .initial, appearance: RendererAppearance())
        let initial = scene.modelTransform
        var orbit = RendererOrbit.initial
        orbit.rotate(horizontal: 0.72, vertical: 0.2)
        scene.apply(orbit: orbit, appearance: RendererAppearance())
        XCTAssertNotEqual(scene.modelTransform, initial)
        XCTAssertTrue(finite(scene.modelTransform))
        let transform = scene.modelTransform
        let mesh = scene.mannequin.mesh
        for x in [-mesh.maximum.x, mesh.maximum.x] {
            for y in [mesh.minimum.y, mesh.maximum.y] {
                for z in [mesh.minimum.z, mesh.maximum.z] {
                    let point = scene.viewProjection * scene.modelTransform * SIMD4<Float>(x, y, z, 1)
                    XCTAssertTrue(point.x.isFinite && point.y.isFinite && point.z.isFinite && point.w.isFinite)
                    XCTAssertGreaterThan(point.w, 0)
                    XCTAssertGreaterThanOrEqual(point.z / point.w, 0)
                    XCTAssertLessThanOrEqual(point.z / point.w, 1)
                    XCTAssertLessThanOrEqual(abs(point.x / point.w), 1.05)
                    XCTAssertLessThanOrEqual(abs(point.y / point.w), 1.05)
                }
            }
        }
        orbit.reset()
        scene.apply(orbit: orbit, appearance: RendererAppearance())
        XCTAssertEqual(scene.modelTransform, initial)
        XCTAssertNotEqual(transform, initial)
        XCTAssertTrue(scene.camera.position.x.isFinite && scene.camera.position.z.isFinite)
        XCTAssertTrue(finite(scene.viewProjection))
        scene.dispose()
    }

    func testInvalidGarmentCanRecoverWithoutRebuildingMannequin() throws {
        let scene = try RendererSceneSession()
        let mannequin = scene.mannequin
        let mannequinBuffer = try XCTUnwrap(mannequin.vertexBuffer)
        XCTAssertThrowsError(try scene.replaceGarment(asset: .mannequinFixture)) { error in
            XCTAssertEqual(error as? RendererFailure, .unsupportedAsset)
        }
        XCTAssertNil(scene.garment)
        XCTAssertEqual(scene.garmentFailure, .unsupportedAsset)
        XCTAssertTrue(scene.mannequin === mannequin)
        XCTAssertTrue(mannequinBuffer === scene.mannequin.vertexBuffer)
        try scene.replaceGarment(asset: .garmentFixture)
        XCTAssertNotNil(scene.garment)
        XCTAssertNil(scene.garmentFailure)
        XCTAssertTrue(mannequinBuffer === scene.mannequin.vertexBuffer)
        try scene.replaceGarment(asset: nil)
        XCTAssertNil(scene.garment)
        XCTAssertEqual(scene.garmentFailure, .missingAsset)
        try scene.replaceGarment(asset: .garmentFixture)
        XCTAssertNil(scene.garmentFailure)
        scene.dispose()
    }

    func testMissingGarmentLeavesMannequinAvailable() throws {
        let inputs: [(RendererAssetDescriptor?, RendererFailure)] = [
            (nil, .missingAsset), (.mannequinFixture, .unsupportedAsset)
        ]
        for (asset, failure) in inputs {
            let scene = try RendererSceneSession(garmentAsset: asset)
            XCTAssertNil(scene.garment)
            XCTAssertEqual(scene.garmentFailure, failure)
            let mannequinBuffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
            try scene.replaceGarment(asset: .garmentFixture)
            XCTAssertNotNil(scene.garment?.indexBuffer)
            XCTAssertTrue(mannequinBuffer === scene.mannequin.vertexBuffer)
            scene.dispose()
        }
    }

    func testDisposeReleasesBuffersAndPreventsCallbacksOrResurrection() throws {
        let scene = try RendererSceneSession()
        let mannequin = scene.mannequin
        let garment = try XCTUnwrap(scene.garment)
        scene.dispose()
        scene.dispose()
        XCTAssertNil(mannequin.vertexBuffer)
        XCTAssertNil(mannequin.indexBuffer)
        XCTAssertNil(garment.vertexBuffer)
        XCTAssertNil(garment.indexBuffer)
        XCTAssertNil(scene.garment)
        let transform = scene.modelTransform
        scene.apply(orbit: RendererOrbit(yaw: 1, pitch: 0), appearance: RendererAppearance())
        XCTAssertEqual(scene.modelTransform, transform)
        XCTAssertThrowsError(try scene.replaceGarment(asset: .garmentFixture))
        XCTAssertNil(scene.onFailure)
    }

    func testRepeatedSessionsReleaseViewAndSessionOwnership() throws {
        for _ in 0..<3 {
            var session: RendererSceneSession? = try RendererSceneSession()
            weak var weakSession = session
            weak var weakView = session?.view
            session?.dispose()
            session = nil
            XCTAssertNil(weakSession)
            XCTAssertNil(weakView)
        }
    }

    func testViewportResizeKeepsExtremeOrbitTransformsFinite() throws {
        let scene = try RendererSceneSession()
        defer { scene.dispose() }
        scene.apply(orbit: RendererOrbit(yaw: .greatestFiniteMagnitude, pitch: .greatestFiniteMagnitude),
                    appearance: RendererAppearance())
        for size in [
            CGSize.zero, CGSize(width: CGFloat.nan, height: 400), CGSize(width: 400, height: CGFloat.infinity),
            CGSize(width: 1, height: 500), CGSize(width: 500, height: 1), CGSize(width: 300, height: 400)
        ] {
            scene.mtkView(scene.view, drawableSizeWillChange: size)
            XCTAssertTrue(finite(scene.modelTransform))
            XCTAssertTrue(finite(scene.viewProjection))
            XCTAssertTrue(scene.camera.position.z.isFinite)
            let head = scene.viewProjection * scene.modelTransform * SIMD4<Float>(0, 1.75, 0, 1)
            XCTAssertGreaterThan(head.w, 0)
            XCTAssertGreaterThanOrEqual(head.z / head.w, 0)
            XCTAssertLessThanOrEqual(head.z / head.w, 1)
        }
    }

    private func finite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }
    }
}
#endif
