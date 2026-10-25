#if DEBUG
import Combine
import CryptoKit
import Foundation
import Metal
import XCTest
@testable import FitCheck

@MainActor
final class ReplayRenderingLifecycleTests: XCTestCase {
    private func result(_ id: ReplayID) async throws -> ReplayGeometryResult {
        try await SyntheticReplayReconstructor().reconstruct(id)
    }

    func testEveryGPUElementIsDerivedReplayMeshAndCannotInstallGarment() async throws {
        let a = try await result(.columnA)
        let b = try await result(.columnB)
        XCTAssertNotEqual(a.mesh, b.mesh)
        XCTAssertEqual(a.stages, ReplayStage.allCases)
        for reconstructed in [a, b] {
            let scene = try RendererSceneSession(replay: reconstructed)
            defer { scene.dispose() }
            XCTAssertTrue(scene.hasSyntheticGeometry)
            XCTAssertNil(scene.garment)
            let object = scene.mannequin
            XCTAssertEqual(object.mesh.vertices.count, reconstructed.mesh.vertices.count)
            let vertices = try XCTUnwrap(object.vertexBuffer).contents().bindMemory(to: RendererVertex.self, capacity: reconstructed.mesh.vertices.count)
            let indices = try XCTUnwrap(object.indexBuffer).contents().bindMemory(to: UInt16.self, capacity: reconstructed.mesh.indices.count)
            for i in reconstructed.mesh.vertices.indices {
                XCTAssertEqual(vertices[i].position, reconstructed.mesh.vertices[i].position)
                XCTAssertEqual(vertices[i].normal, reconstructed.mesh.vertices[i].normal)
            }
            for i in reconstructed.mesh.indices.indices { XCTAssertEqual(indices[i], reconstructed.mesh.indices[i]) }
            XCTAssertNotEqual(object.mesh.vertices.count, RendererProceduralAssets.mannequin().vertices.count)
            XCTAssertThrowsError(try scene.replaceGarment(asset: .garmentFixture)) {
                XCTAssertEqual($0 as? RendererFailure, .unsupportedAsset)
            }
            scene.apply(orbit: .initial, appearance: RendererAppearance())
            let initial = scene.modelTransform
            var orbit = RendererOrbit.initial
            orbit.rotate(horizontal: 0.5, vertical: 0.1)
            scene.apply(orbit: orbit, appearance: RendererAppearance())
            XCTAssertNotEqual(scene.modelTransform, initial)
            orbit.reset()
            scene.apply(orbit: orbit, appearance: RendererAppearance())
            XCTAssertEqual(scene.modelTransform, initial)
            scene.dispose()
            XCTAssertNil(object.vertexBuffer)
            XCTAssertNil(object.indexBuffer)
            XCTAssertNil(scene.view.delegate)
        }
    }

    func testReplayBytesCannotForgeS2BArtifactEvenWithRecomputedIntegrity() async throws {
        let reconstructed = try await result(.columnA)
        let approved = try GeometryKernel.generate(GeometryKernel.reviewedFixture(.surfaceA))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: SyntheticArtifactCodec.encode(approved)) as? [String: Any])
        let mesh = reconstructed.mesh
        var payload = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { payload.append(contentsOf: $0) }
        }
        append(UInt32(mesh.vertices.count)); append(UInt32(mesh.indices.count))
        for vertex in mesh.vertices {
            append(vertex.position.x.bitPattern); append(vertex.position.y.bitPattern); append(vertex.position.z.bitPattern)
            append(vertex.normal.x.bitPattern); append(vertex.normal.y.bitPattern); append(vertex.normal.z.bitPattern)
        }
        for index in mesh.indices { append(index) }
        append(mesh.minimum.x.bitPattern); append(mesh.minimum.y.bitPattern); append(mesh.minimum.z.bitPattern)
        append(mesh.maximum.x.bitPattern); append(mesh.maximum.y.bitPattern); append(mesh.maximum.z.bitPattern)
        envelope["payload"] = payload.base64EncodedString()
        envelope["digest"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        envelope["vertexCount"] = mesh.vertices.count
        envelope["indexCount"] = mesh.indices.count
        envelope["minimum"] = [mesh.minimum.x, mesh.minimum.y, mesh.minimum.z]
        envelope["maximum"] = [mesh.maximum.x, mesh.maximum.y, mesh.maximum.z]
        let forged = try JSONSerialization.data(withJSONObject: envelope)
        XCTAssertThrowsError(try SyntheticArtifactCodec.decode(forged)) {
            XCTAssertEqual($0 as? SyntheticArtifactFailure, .incompatibleArtifact)
        }
        XCTAssertEqual(AvatarEntryResolver.destination(for: nil), .createAvatar)
    }

    func testActualFailureClearsOldMeshAndSupportedReplayRecovers() async throws {
        let model = SpatialReplayLabModel()
        defer { model.close() }
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .ready)
        let old = try XCTUnwrap(model.session)
        model.select(.missingDepth)
        XCTAssertNil(model.result)
        XCTAssertNil(model.session)
        XCTAssertNil(old.mannequin.vertexBuffer)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .failed(.replay(.missingDepth)))
        model.select(.columnB)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.result?.id, .columnB)
        XCTAssertNotEqual(model.session?.id, old.id)
    }

    func testRapidSwitchingAdmitsOnePhysicalWorkerAndOnlyLatestReply() async throws {
        let service = DeferredReplayService()
        let a = try await result(.columnA), b = try await result(.columnB)
        let model = SpatialReplayLabModel(service: service)
        defer { model.close() }
        let first = try XCTUnwrap(model.open(isActive: true))
        await service.waitForCalls(1)
        model.select(.columnB); model.select(.badCalibration); model.select(.columnA); model.select(.columnB)
        let before = await service.requests
        XCTAssertEqual(before, [.columnA])
        await service.complete(.success(a))
        await first.value
        await service.waitForCalls(2)
        let after = await service.requests
        XCTAssertEqual(after, [.columnA, .columnB])
        XCTAssertNil(model.result)
        XCTAssertNil(model.session)
        let current = try XCTUnwrap(model.open(isActive: true))
        await service.complete(.success(b))
        await current.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.result?.id, .columnB)
    }

    func testBackgroundDisposesAndReconstructsOnlyCurrentReplayWithPreservedOrbit() async throws {
        let model = SpatialReplayLabModel()
        defer { model.close() }
        await model.open(isActive: true)?.value
        model.select(.columnB)
        await model.open(isActive: true)?.value
        let old = try XCTUnwrap(model.session)
        model.rotate(horizontal: 0.7, vertical: 0.1)
        let orbit = model.orbit
        model.setActive(false)
        XCTAssertEqual(model.state, .suspended)
        XCTAssertNil(model.result)
        XCTAssertNil(old.mannequin.vertexBuffer)
        XCTAssertNil(old.mannequin.indexBuffer)
        model.setActive(true)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.result?.id, .columnB)
        XCTAssertEqual(model.orbit, orbit)
        XCTAssertNotEqual(model.session?.id, old.id)
        model.close()
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.result?.id, .columnA)
        XCTAssertEqual(model.orbit, .initial)
    }

    func testWrongReplyRenderFailureAndStaleCallbacksCannotClaimReady() async throws {
        let service = DeferredReplayService()
        let b = try await result(.columnB)
        let model = SpatialReplayLabModel(service: service)
        defer { model.close() }
        let first = try XCTUnwrap(model.open(isActive: true))
        await service.waitForCalls(1)
        await service.complete(.success(b)); await first.value
        XCTAssertEqual(model.state, .failed(.unexpected))
        XCTAssertNil(model.session)
        let real = SpatialReplayLabModel()
        defer { real.close() }
        await real.open(isActive: true)?.value
        let old = try XCTUnwrap(real.session)
        let callback = try XCTUnwrap(old.onFailure)
        callback(.graphicsUnavailable)
        XCTAssertEqual(real.state, .failed(.rendering(.graphicsUnavailable)))
        XCTAssertNil(real.result)
        XCTAssertNil(old.mannequin.vertexBuffer)
        await real.run()?.value
        let replacement = try XCTUnwrap(real.session)
        callback(.sceneCreationFailed)
        XCTAssertTrue(real.session === replacement)
        XCTAssertEqual(real.state, .ready)
        let unavailable = SpatialReplayLabModel(makeScene: { _ in throw RendererFailure.graphicsUnavailable })
        defer { unavailable.close() }
        await unavailable.open(isActive: true)?.value
        XCTAssertEqual(unavailable.state, .failed(.rendering(.graphicsUnavailable)))
        XCTAssertNil(unavailable.result)
    }

    func testDismissedOwnerIsNotRetainedAndLateResultCannotCreateScene() async throws {
        let service = DeferredReplayService()
        let a = try await result(.columnA)
        var model: SpatialReplayLabModel? = SpatialReplayLabModel(service: service)
        let task = try XCTUnwrap(model?.open(isActive: true))
        await service.waitForCalls(1)
        model?.close()
        weak var owner = model
        model = nil
        XCTAssertNil(owner)
        await service.complete(.success(a))
        await task.value
    }
}

private actor DeferredReplayService: ReplayReconstructing {
    private(set) var requests: [ReplayID] = []
    private var pending: [CheckedContinuation<ReplayGeometryResult, Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func reconstruct(_ replay: ReplayID) async throws -> ReplayGeometryResult {
        requests.append(replay)
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = waiters.filter { requests.count >= $0.0 }
            waiters.removeAll { requests.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func complete(_ result: Result<ReplayGeometryResult, Error>) { pending.removeFirst().resume(with: result) }
}
#endif
