#if DEBUG
import Metal
import simd
import XCTest
@testable import FitCheck

@MainActor
final class GeometryRendererTests: XCTestCase {
    func testAdapterAndMetalBuffersContainExactGeneratedMesh() async throws {
        let result = try await SyntheticGeometryGenerator().generate(.surfaceA)
        let mesh = try GeometryRendererAdapter.mesh(from: result)
        let scene = try RendererSceneSession(geometry: result)
        defer { scene.dispose() }

        XCTAssertTrue(scene.hasSyntheticGeometry)
        XCTAssertNil(scene.garment)
        XCTAssertEqual(scene.mannequin.mesh.vertices.count, result.mesh.vertices.count)
        XCTAssertEqual(scene.mannequin.mesh.indices, result.mesh.indices)
        let vertexBuffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
        let indexBuffer = try XCTUnwrap(scene.mannequin.indexBuffer)
        let vertexPointer = vertexBuffer.contents().bindMemory(to: RendererVertex.self, capacity: mesh.vertices.count)
        let indexPointer = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: mesh.indices.count)
        for index in mesh.vertices.indices {
            XCTAssertEqual(vertexPointer[index].position, mesh.vertices[index].position)
            XCTAssertEqual(vertexPointer[index].normal, mesh.vertices[index].normal)
        }
        for index in mesh.indices.indices { XCTAssertEqual(indexPointer[index], mesh.indices[index]) }
        XCTAssertNotEqual(mesh.vertices.count, RendererProceduralAssets.mannequin().vertices.count,
                          "Generated geometry cannot be the existing mannequin under a new label")
        XCTAssertThrowsError(try scene.replaceGarment(asset: .garmentFixture)) {
            XCTAssertEqual($0 as? RendererFailure, .unsupportedAsset)
        }
        XCTAssertThrowsError(try RendererAssetDescriptor.garmentFixture.validate(for: .syntheticGeometry))
    }

    func testFixturesDifferWithSameFixedMaterialAndFiniteFramingOrbitAndDispose() async throws {
        let first = try await SyntheticGeometryGenerator().generate(.surfaceA)
        let second = try await SyntheticGeometryGenerator().generate(.surfaceB)
        let a = try RendererSceneSession(geometry: first)
        let b = try RendererSceneSession(geometry: second)
        defer { a.dispose(); b.dispose() }
        XCTAssertNotEqual(a.mannequin.mesh.vertices.map(\.position), b.mannequin.mesh.vertices.map(\.position))
        XCTAssertEqual(a.mannequin.color, b.mannequin.color)
        XCTAssertNotNil(a.mannequin.vertexBuffer)
        XCTAssertNil(a.garment)
        for scene in [a, b] {
            scene.apply(orbit: .initial, appearance: RendererAppearance())
            XCTAssertTrue(finite(scene.viewProjection))
            XCTAssertTrue(finite(scene.modelTransform))
            var orbit = RendererOrbit.initial
            let initial = scene.modelTransform
            orbit.rotate(horizontal: 0.7, vertical: 0.15)
            scene.apply(orbit: orbit, appearance: RendererAppearance())
            XCTAssertNotEqual(scene.modelTransform, initial)
            for x in [scene.mannequin.mesh.minimum.x, scene.mannequin.mesh.maximum.x] {
                for y in [scene.mannequin.mesh.minimum.y, scene.mannequin.mesh.maximum.y] {
                    for z in [scene.mannequin.mesh.minimum.z, scene.mannequin.mesh.maximum.z] {
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
        }
        var session: RendererSceneSession? = try RendererSceneSession(geometry: first)
        weak var weakSession = session
        weak var weakView = session?.view
        let object = try XCTUnwrap(session?.mannequin)
        XCTAssertNotNil(session?.view)
        session?.dispose()
        XCTAssertTrue(session?.isDisposed == true)
        XCTAssertNil(object.vertexBuffer)
        XCTAssertNil(object.indexBuffer)
        XCTAssertNil(session?.view.delegate)
        let transform = try XCTUnwrap(session?.modelTransform)
        session?.apply(orbit: RendererOrbit(yaw: 1, pitch: 0), appearance: RendererAppearance())
        XCTAssertEqual(session?.modelTransform, transform)
        XCTAssertThrowsError(try session?.replaceGarment(asset: .garmentFixture)) { error in
            XCTAssertEqual(error as? RendererFailure, .sceneCreationFailed)
        }
        session = nil
        XCTAssertNil(weakSession)
        XCTAssertNil(weakView)
    }

    private func finite(_ matrix: simd_float4x4) -> Bool {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
            .allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }
    }
}
#endif
