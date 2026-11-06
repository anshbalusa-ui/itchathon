#if DEBUG
import Metal
import simd
import XCTest
@testable import FitCheck

@MainActor
final class FridayDemoFramingTests: XCTestCase {
    func testFittedAvatarAndReplayRemainFullyVisibleWithoutChangingTheirGPUVertices() async throws {
        let generator = SyntheticGeometryGenerator()
        let reconstructor = SyntheticReplayReconstructor()
        for fixture in [GeometryFixtureID.surfaceA, .surfaceB] {
            let geometry = try await generator.generate(fixture)
            let scene = try RendererSceneSession(geometry: geometry, fitSurface: true)
            try verifyFraming(scene)
            scene.dispose()
        }
        for replay in [ReplayID.columnA, .columnB] {
            let result = try await reconstructor.reconstruct(replay)
            let scene = try RendererSceneSession(replay: result, fitSurface: true)
            try verifyFraming(scene)
            scene.dispose()
        }
    }

    private func verifyFraming(_ scene: RendererSceneSession) throws {
        let mesh = scene.mannequin.mesh
        let buffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
        let vertices = buffer.contents().bindMemory(to: RendererVertex.self, capacity: mesh.vertices.count)
        for aspect: Float in [0.5, 1, 2] {
            let size = CGSize(width: CGFloat(400 * aspect), height: 400)
            scene.view.drawableSize = size
            scene.mtkView(scene.view, drawableSizeWillChange: size)
            for yaw: Float in [0, .pi / 2, .pi] {
                for pitch: Float in [-RendererOrbit.maximumPitch, 0, RendererOrbit.maximumPitch] {
                    scene.apply(orbit: RendererOrbit(yaw: yaw, pitch: pitch), appearance: RendererAppearance())
                    XCTAssertLessThan(scene.camera.position.z, RendererSceneConfiguration.standard.cameraDistance,
                                      "Partial surfaces need closer framing than a whole mannequin")
                    for index in mesh.vertices.indices {
                        let position = mesh.vertices[index].position
                        XCTAssertEqual(vertices[index].position, position, "Framing must not alter admitted GPU geometry")
                        let projected = scene.viewProjection * scene.modelTransform * SIMD4<Float>(position.x, position.y, position.z, 1)
                        XCTAssertGreaterThan(projected.w, 0)
                        let ndc = projected / projected.w
                        XCTAssertTrue(ndc.x.isFinite && ndc.y.isFinite && ndc.z.isFinite)
                        XCTAssertLessThanOrEqual(abs(ndc.x), 1)
                        XCTAssertLessThanOrEqual(abs(ndc.y), 1)
                        XCTAssertGreaterThanOrEqual(ndc.z, 0)
                        XCTAssertLessThanOrEqual(ndc.z, 1)
                    }
                }
            }
        }
    }
}
#endif
