#if DEBUG
import simd
import XCTest
@testable import FitCheck

@MainActor
final class MeasurementAvatarRendererTests: XCTestCase {
    func testGeneratedAnatomyAndClothingRemainFramedAtSizeAndOrbitLimits() async throws {
        let large = try MeasurementAvatarInput(heightCM: 210, chestCM: 135, waistCM: 120, hipsCM: 140, shouldersCM: 58)
        for input in [MeasurementAvatarInput.sampleA, .sampleB, large] {
            let generated = try await MeasurementAvatarGenerator.shared.generate(input)
            let scene = try RendererSceneSession(measurementAvatar: generated)
            defer { scene.dispose() }
            let meshes = [generated.body, generated.shirt, generated.shorts]
            XCTAssertEqual(scene.camera.target.y, Float(input.heightCM / 200), accuracy: 0.001)
            for size in [CGSize(width: 220, height: 400), CGSize(width: 375, height: 340), CGSize(width: 430, height: 210)] {
                scene.view.drawableSize = size
                for yaw in [Float(0), .pi / 4, .pi / 2, .pi, -.pi / 2] {
                    for pitch in [-RendererOrbit.maximumPitch, 0, RendererOrbit.maximumPitch] {
                        scene.apply(orbit: RendererOrbit(yaw: yaw, pitch: pitch), appearance: RendererAppearance())
                        let transform = scene.viewProjection * scene.modelTransform
                        var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                        var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                        var forward = true
                        for mesh in meshes {
                            for vertex in mesh.vertices {
                                let point = vertex.position
                                let clip = transform * SIMD4<Float>(point.x, point.y, point.z, 1)
                                guard clip.w.isFinite, clip.w > 0 else { forward = false; continue }
                                let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
                                low = simd_min(low, ndc)
                                high = simd_max(high, ndc)
                            }
                        }
                        let context = "Height \(input.heightCM), viewport \(size), yaw \(yaw), pitch \(pitch)"
                        XCTAssertTrue(forward, context)
                        XCTAssertGreaterThanOrEqual(low.x, -1, context)
                        XCTAssertGreaterThanOrEqual(low.y, -1, context)
                        XCTAssertLessThanOrEqual(high.x, 1, context)
                        XCTAssertLessThanOrEqual(high.y, 1, context)
                        XCTAssertGreaterThanOrEqual(low.z, 0, context)
                        XCTAssertLessThanOrEqual(high.z, 1, context)
                    }
                }
            }
        }
    }

    func testEditableMeasurementsDoNotAcquireAuthoredFitMapAndDisposedScenesReleaseTheirResources() async throws {
        let generated = try await MeasurementAvatarGenerator.shared.generate(.sampleB)
        let scene = try RendererSceneSession(measurementAvatar: generated)
        let garment = try XCTUnwrap(scene.garment)
        XCTAssertNil(garment.clearanceBuffer, "Changing geometry invalidates the old authored clearance field")
        XCTAssertThrowsError(try scene.applyHuman(orbit: .initial, appearance: RendererAppearance(), region: .chest, mapVisible: true)) {
            XCTAssertEqual($0 as? RendererFailure, .unsupportedAsset)
        }
        XCTAssertThrowsError(try scene.replaceGarment(asset: .garmentFixture))
        scene.dispose()
        XCTAssertTrue(scene.isDisposed)
        XCTAssertNil(scene.mannequin.vertexBuffer)
        XCTAssertNil(scene.mannequin.indexBuffer)
        XCTAssertNil(garment.vertexBuffer)
        XCTAssertNil(garment.indexBuffer)
        XCTAssertNil(scene.view.delegate)
        XCTAssertNil(scene.garment)
    }
}
#endif
