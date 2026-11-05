#if DEBUG
import Metal
import simd
import XCTest
@testable import FitCheck

@MainActor
final class HumanShowcaseModelTests: XCTestCase {
    func testHumanSceneUsesAnatomicalGPUVerticesAndSeparateAuthoredClearanceBuffer() throws {
        let meshes = try HumanShowcaseAssets.load()
        let scene = try RendererSceneSession(human: meshes, garment: .shirt)
        defer { scene.dispose() }
        XCTAssertTrue(scene.isHumanAvatarScene)
        XCTAssertFalse(scene.hasSyntheticGeometry)
        XCTAssertEqual(scene.garmentAssetIdentifier, HumanShowcaseGarment.shirt.assetIdentifier)
        let bodyBuffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
        let body = bodyBuffer.contents().bindMemory(to: RendererVertex.self, capacity: meshes.body.vertices.count)
        for index in meshes.body.vertices.indices {
            XCTAssertEqual(body[index].position, meshes.body.vertices[index].position)
            XCTAssertEqual(body[index].normal, meshes.body.vertices[index].normal)
        }
        let garment = try XCTUnwrap(scene.garment)
        let gaps = try XCTUnwrap(meshes.shirt.sampleClearance)
        let buffer = try XCTUnwrap(garment.clearanceBuffer)
        let gpu = buffer.contents().bindMemory(to: Float.self, capacity: gaps.count)
        for index in gaps.indices { XCTAssertEqual(gpu[index], gaps[index]) }
        XCTAssertThrowsError(try scene.replaceGarment(asset: .garmentFixture),
                             "The human illustration cannot silently substitute the old diagnostic garment")
        let diagnostic = try RendererSceneSession()
        defer { diagnostic.dispose() }
        XCTAssertThrowsError(try diagnostic.applyHuman(orbit: .initial, appearance: RendererAppearance(),
                                                       region: .chest, mapVisible: true),
                             "A fit map cannot be attached to an unrelated diagnostic or scanner scene")
    }

    func testWholeHumanAndClothingRemainInsideFrustumAcrossViewportAndOrbitLimits() throws {
        let meshes = try HumanShowcaseAssets.load()
        let scene = try RendererSceneSession(human: meshes, garment: .shirt)
        defer { scene.dispose() }
        let geometry = [meshes.body, meshes.shirt, meshes.vest, meshes.shorts]
        for size in [CGSize(width: 220, height: 400), CGSize(width: 375, height: 340), CGSize(width: 400, height: 220)] {
            scene.view.drawableSize = size
            for octant in 0..<8 {
                let yaw = Float(octant) * .pi / 4
                for pitch in [-RendererOrbit.maximumPitch, 0, RendererOrbit.maximumPitch] {
                    try scene.applyHuman(orbit: RendererOrbit(yaw: yaw, pitch: pitch), appearance: RendererAppearance(),
                                         region: .whole, mapVisible: false)
                    let transform = scene.viewProjection * scene.modelTransform
                    var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
                    var high = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
                    for mesh in geometry {
                        for vertex in mesh.vertices {
                            let p = vertex.position
                            let clip = transform * SIMD4<Float>(p.x, p.y, p.z, 1)
                            guard clip.w.isFinite, clip.w > 0 else {
                                XCTFail("The human must remain in front of the camera")
                                continue
                            }
                            let ndc = SIMD3<Float>(clip.x, clip.y, clip.z) / clip.w
                            low = simd_min(low, ndc)
                            high = simd_max(high, ndc)
                        }
                    }
                    let context = "\(size), yaw \(yaw), pitch \(pitch)"
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

    func testRegionCameraCentersRotatedAnatomyAndResetRestoresWholeBodyWithoutMeshMutation() async throws {
        let model = try makeModel()
        await model.open(isActive: true)?.value
        let scene = try XCTUnwrap(model.session)
        defer { model.close() }
        let original = scene.viewProjection
        let vertices = try XCTUnwrap(scene.mannequin.vertexBuffer)
        let garmentVertices = try XCTUnwrap(scene.garment?.vertexBuffer)
        for region in HumanBodyRegion.allCases where region != .whole {
            model.focus(region)
            model.rotate(horizontal: 0.6, vertical: 0.1)
            let target = region.target
            let projected = scene.viewProjection * scene.modelTransform * SIMD4<Float>(target.x, target.y, target.z, 1)
            XCTAssertEqual(projected.x / projected.w, 0, accuracy: 0.0001)
            XCTAssertEqual(projected.y / projected.w, 0, accuracy: 0.0001)
            XCTAssertGreaterThan(projected.z / projected.w, 0)
            XCTAssertLessThan(projected.z / projected.w, 1)
            XCTAssertLessThan(scene.camera.position.z - scene.camera.target.z, RendererSceneConfiguration.standard.cameraDistance)
            XCTAssertTrue(scene.mannequin.vertexBuffer === vertices)
            XCTAssertTrue(scene.garment?.vertexBuffer === garmentVertices)
        }
        model.resetView()
        XCTAssertEqual(model.region, .whole)
        XCTAssertEqual(scene.viewProjection, original)
        XCTAssertTrue(scene.mannequin.vertexBuffer === vertices)
    }

    func testBackgroundAndNavigationReopeningRestoreInspectionAndDisposeOldGPUOwnership() async throws {
        let model = try makeModel()
        await model.open(isActive: true)?.value
        let first = try XCTUnwrap(model.session)
        model.setFitMapVisible(true)
        model.focus(.waist)
        model.rotate(horizontal: 0.4, vertical: 0)
        let camera = first.camera
        let transform = first.modelTransform
        let gapObject = try XCTUnwrap(first.garment)
        model.setActive(false)
        XCTAssertNil(model.session)
        XCTAssertTrue(first.isDisposed)
        XCTAssertNil(first.mannequin.vertexBuffer)
        XCTAssertNil(gapObject.clearanceBuffer)
        model.setActive(true)
        await model.open(isActive: true)?.value
        let second = try XCTUnwrap(model.session)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(second.camera.target, camera.target)
        XCTAssertEqual(second.camera.position, camera.position)
        XCTAssertEqual(second.modelTransform, transform)
        XCTAssertTrue(model.fitMapVisible)
        XCTAssertEqual(model.region, .waist)
        model.close()
        XCTAssertTrue(second.isDisposed)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.region, .waist)
        XCTAssertTrue(model.fitMapVisible)
        XCTAssertEqual(model.session?.camera.target, camera.target)
        model.close()
    }

    func testRejectedAssetShowsNoSceneAndRetryCanRecoverWithoutFallbackBody() async throws {
        let meshes = try HumanShowcaseAssets.load()
        let loader = RecoveringHumanLoader(meshes: meshes)
        let model = try makeModel(loader: loader)
        await model.open(isActive: true)?.value
        if case .failed = model.state {} else { XCTFail("Admission failure must be recoverable, not a fake body") }
        XCTAssertNil(model.session)
        model.retry()
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertTrue(model.session?.isHumanAvatarScene == true)
        XCTAssertEqual(model.session?.mannequin.mesh.vertices.first?.position, meshes.body.vertices.first?.position)
        model.close()
    }

    private func makeModel(loader: any HumanShowcaseLoading = HumanShowcaseAssetStore.shared) throws -> HumanShowcaseModel {
        let selection = FridayDemoSelection()
        return HumanShowcaseModel(preview: try XCTUnwrap(selection.preview), loader: loader)
    }
}

private actor RecoveringHumanLoader: HumanShowcaseLoading {
    private let meshes: HumanShowcaseMeshes
    private var rejected = false
    init(meshes: HumanShowcaseMeshes) { self.meshes = meshes }
    func load() throws -> HumanShowcaseMeshes {
        if !rejected { rejected = true; throw HumanShowcaseAssetFailure.rejectedPayload }
        return meshes
    }
}
#endif
