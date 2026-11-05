#if DEBUG
import Combine
import Foundation
import Metal
import XCTest
@testable import FitCheck

@MainActor
final class SyntheticArtifactLabLifecycleTests: XCTestCase {
    private func artifact(_ fixture: GeometryFixtureID) async throws -> VerifiedSyntheticArtifact {
        try SyntheticArtifactCodec.decode(SyntheticArtifactCodec.encode(try await SyntheticGeometryGenerator().generate(fixture)))
    }

    func testFreshOwnerLoadsActualDiskMeshIntoEveryMetalElementAndDeletionReleasesIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SyntheticArtifactRepository(directoryURL: directory)
        let first = AvatarGeometryLabModel(artifactStore: store)
        await first.open(isActive: true)?.value
        first.select(.surfaceB)
        await first.open(isActive: true)?.value
        let b = try XCTUnwrap(first.result)
        await first.saveArtifact()?.value
        guard case .saved(let saved) = first.artifactState else { return XCTFail("Real file publication must finish before reporting saved") }
        let bytes = try Data(contentsOf: directory.appendingPathComponent(SyntheticArtifactRepository.artifactFilename))
        XCTAssertEqual(try SyntheticArtifactCodec.decode(bytes).mesh, b.mesh)
        first.close()

        let cold = AvatarGeometryLabModel(artifactStore: SyntheticArtifactRepository(directoryURL: directory))
        defer { cold.close() }
        await cold.open(isActive: true)?.value
        let generatedA = try XCTUnwrap(cold.result)
        await cold.loadArtifact()?.value
        let loaded = try XCTUnwrap(cold.loadedArtifact)
        XCTAssertEqual(cold.artifactState, .loaded(saved))
        XCTAssertEqual(loaded.mesh, b.mesh)
        XCTAssertNotEqual(loaded.mesh, generatedA.mesh)
        XCTAssertNil(cold.result, "Disk-loaded geometry must not be passed off as a generated result")
        let scene = try XCTUnwrap(cold.session)
        let object = scene.mannequin
        let vertices = try XCTUnwrap(object.vertexBuffer).contents().bindMemory(to: RendererVertex.self, capacity: loaded.mesh.vertices.count)
        let indices = try XCTUnwrap(object.indexBuffer).contents().bindMemory(to: UInt16.self, capacity: loaded.mesh.indices.count)
        for i in loaded.mesh.vertices.indices {
            XCTAssertEqual(vertices[i].position, loaded.mesh.vertices[i].position)
            XCTAssertEqual(vertices[i].normal, loaded.mesh.vertices[i].normal)
        }
        for i in loaded.mesh.indices.indices { XCTAssertEqual(indices[i], loaded.mesh.indices[i]) }
        await cold.deleteArtifact()?.value
        XCTAssertEqual(cold.artifactState, .deleted)
        XCTAssertNil(cold.loadedArtifact)
        XCTAssertNil(cold.session)
        XCTAssertNil(object.vertexBuffer)
        XCTAssertNil(object.indexBuffer)
        let after = try await SyntheticArtifactRepository(directoryURL: directory).load()
        XCTAssertNil(after)
        XCTAssertEqual(AvatarEntryResolver.destination(for: nil), .createAvatar)
        let metadata = AvatarProfileRecord(schemaVersion: 1, createdAt: Date(timeIntervalSince1970: 0),
            captureMethod: .lidarFrontAndSide, evidenceStatus: .usableForIllustrativePreview,
            modelAssetIdentifier: "synthetic-metadata-only", normalizedShapeParameters: ["synthetic-control": 0.1])
        XCTAssertEqual(AvatarEntryResolver.destination(for: metadata), .previewUnavailable,
                       "A synthetic artifact must not authorize saved personal avatar readiness")
    }

    func testCancelledSaveCannotReportOldAAsSavedBAndNextSaveCanFinish() async throws {
        let store = DeferredArtifactStore()
        let a = try await artifact(.surfaceA)
        let b = try await artifact(.surfaceB)
        let model = AvatarGeometryLabModel(artifactStore: store)
        defer { model.close() }
        await model.open(isActive: true)?.value
        let saveA = try XCTUnwrap(model.saveArtifact())
        await store.waitForEvents(1)
        XCTAssertNil(model.saveArtifact(), "A rapid duplicate save must not start another writer")
        XCTAssertNil(model.loadArtifact(), "Load cannot overlap an unacknowledged save")
        model.select(.surfaceB)
        await model.open(isActive: true)?.value
        await store.completeSave(a.identity)
        await saveA.value
        XCTAssertEqual(model.artifactState, .idle)
        XCTAssertEqual(model.result?.fixture, .surfaceB)
        let saveB = try XCTUnwrap(model.saveArtifact())
        await store.waitForEvents(2)
        let fixtures = await store.savedFixtures
        XCTAssertEqual(fixtures, [.surfaceA, .surfaceB])
        await store.completeSave(b.identity)
        await saveB.value
        XCTAssertEqual(model.artifactState, .saved(b.identity))
    }

    func testLateLoadAfterSelectionAndDismissalCannotResurrectDiskScene() async throws {
        let store = DeferredArtifactStore()
        let a = try await artifact(.surfaceA)
        let model = AvatarGeometryLabModel(artifactStore: store)
        await model.open(isActive: true)?.value
        let load = try XCTUnwrap(model.loadArtifact())
        await store.waitForEvents(1)
        model.select(.surfaceB)
        await model.open(isActive: true)?.value
        let bScene = try XCTUnwrap(model.session)
        await store.completeLoad(a)
        await load.value
        XCTAssertTrue(model.session === bScene)
        XCTAssertNil(model.loadedArtifact)
        XCTAssertEqual(model.artifactState, .idle)
        let late = try XCTUnwrap(model.loadArtifact())
        await store.waitForEvents(2)
        model.close()
        await store.completeLoad(a)
        await late.value
        XCTAssertNil(model.session)
        XCTAssertNil(model.loadedArtifact)
        XCTAssertEqual(model.state, .idle)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.result?.fixture, .surfaceA)
        XCTAssertNil(model.loadedArtifact)
        model.close()
    }

    func testDeleteWaitsForIgnoringLoadAndSelectionCannotDropDeletion() async throws {
        let store = DeferredArtifactStore()
        let a = try await artifact(.surfaceA)
        let model = AvatarGeometryLabModel(artifactStore: store)
        defer { model.close() }
        await model.open(isActive: true)?.value
        let load = try XCTUnwrap(model.loadArtifact())
        await store.waitForEvents(1)
        model.deleteArtifact()
        let before = await store.events
        XCTAssertEqual(before, ["load"])
        XCTAssertNil(model.session)
        await store.completeLoad(a)
        await load.value
        await store.waitForEvents(2)
        XCTAssertNil(model.loadedArtifact)
        model.select(.surfaceB)
        await model.open(isActive: true)?.value
        let bScene = try XCTUnwrap(model.session)
        let deleted = expectation(description: "accepted deletion finishes after earlier read")
        let observation = model.$artifactState.first(where: { $0 == .deleted }).sink { _ in deleted.fulfill() }
        await store.completeDelete()
        await fulfillment(of: [deleted], timeout: 5)
        withExtendedLifetime(observation) {}
        let events = await store.events
        XCTAssertEqual(events, ["load", "delete"])
        XCTAssertTrue(model.session === bScene)
        XCTAssertNil(model.loadedArtifact)
    }

    func testForegroundReloadUsesOnlyNewDiskReplyAndReleasesPreviousGPU() async throws {
        let store = DeferredArtifactStore()
        let a = try await artifact(.surfaceA)
        let b = try await artifact(.surfaceB)
        let model = AvatarGeometryLabModel(artifactStore: store)
        defer { model.close() }
        await model.open(isActive: true)?.value
        let load = try XCTUnwrap(model.loadArtifact())
        await store.waitForEvents(1)
        model.setActive(false)
        model.setActive(true)
        await store.completeLoad(b)
        await load.value
        await store.waitForEvents(2)
        XCTAssertNil(model.session)
        let ready = expectation(description: "only foreground disk reply may install")
        let observation = model.$state.first(where: { $0 == .ready }).sink { _ in ready.fulfill() }
        await store.completeLoad(a)
        await fulfillment(of: [ready], timeout: 5)
        withExtendedLifetime(observation) {}
        XCTAssertEqual(model.loadedArtifact?.fixture, .surfaceA)
        let scene = try XCTUnwrap(model.session)
        model.rotate(horizontal: 0.4, vertical: 0.1)
        let orbit = model.orbit
        model.setActive(false)
        XCTAssertNil(model.loadedArtifact)
        XCTAssertNil(scene.mannequin.vertexBuffer)
        model.setActive(true)
        await store.waitForEvents(3)
        let resumed = expectation(description: "new scene after saved-artifact foreground reload")
        let resumedObservation = model.$state.first(where: { $0 == .ready }).sink { _ in resumed.fulfill() }
        await store.completeLoad(a)
        await fulfillment(of: [resumed], timeout: 5)
        withExtendedLifetime(resumedObservation) {}
        XCTAssertEqual(model.orbit, orbit)
        XCTAssertNotEqual(model.session?.id, scene.id)
        XCTAssertEqual(model.loadedArtifact?.identity, a.identity)
    }

    func testRealCorruptionPreservesBytesAndRequiresDeleteBeforeReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent(SyntheticArtifactRepository.artifactFilename)
        let corrupt = Data("damaged synthetic artifact".utf8)
        try corrupt.write(to: path)
        let model = AvatarGeometryLabModel(artifactStore: SyntheticArtifactRepository(directoryURL: directory))
        defer { model.close() }
        await model.open(isActive: true)?.value
        await model.loadArtifact()?.value
        XCTAssertEqual(model.artifactState, .failed(.corruptArtifact))
        XCTAssertEqual(model.state, .failed(.artifact(.corruptArtifact)))
        XCTAssertNil(model.session)
        XCTAssertNil(model.result)
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
        await model.generate()?.value
        await model.saveArtifact()?.value
        XCTAssertEqual(model.artifactState, .failed(.corruptArtifact))
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
        await model.deleteArtifact()?.value
        await model.generate()?.value
        await model.saveArtifact()?.value
        guard case .saved = model.artifactState else { return XCTFail("Explicit delete must allow genuine valid recovery") }
        await model.loadArtifact()?.value
        XCTAssertEqual(model.loadedArtifact?.fixture, .surfaceA)
    }

    func testPendingDiskReplyDoesNotRetainDismissedOwnerOrAllocateAnotherScene() async throws {
        let store = DeferredArtifactStore()
        let a = try await artifact(.surfaceA)
        var model: AvatarGeometryLabModel? = AvatarGeometryLabModel(artifactStore: store)
        await model?.open(isActive: true)?.value
        let object = try XCTUnwrap(model?.session?.mannequin)
        let request = try XCTUnwrap(model?.loadArtifact())
        await store.waitForEvents(1)
        model?.close()
        weak var owner = model
        model = nil
        XCTAssertNil(owner)
        XCTAssertNil(object.vertexBuffer)
        XCTAssertNil(object.indexBuffer)
        await store.completeLoad(a)
        await request.value
    }
}

/// Cancellation-ignoring replies exercise UI epochs, not repository correctness.
private actor DeferredArtifactStore: SyntheticArtifactPersisting {
    private(set) var events: [String] = []
    private(set) var savedFixtures: [GeometryFixtureID] = []
    private var saves: [CheckedContinuation<SyntheticArtifactIdentity, Error>] = []
    private var loads: [CheckedContinuation<VerifiedSyntheticArtifact?, Error>] = []
    private var deletes: [CheckedContinuation<Void, Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func save(_ geometry: GeometryResult) async throws -> SyntheticArtifactIdentity {
        savedFixtures.append(geometry.fixture)
        return try await withCheckedThrowingContinuation { continuation in
            saves.append(continuation); events.append("save"); notify()
        }
    }
    func load() async throws -> VerifiedSyntheticArtifact? {
        try await withCheckedThrowingContinuation { continuation in
            loads.append(continuation); events.append("load"); notify()
        }
    }
    func delete() async throws {
        try await withCheckedThrowingContinuation { continuation in
            deletes.append(continuation); events.append("delete"); notify()
        }
    }
    func waitForEvents(_ count: Int) async {
        if events.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func completeSave(_ value: SyntheticArtifactIdentity) { saves.removeFirst().resume(returning: value) }
    func completeLoad(_ value: VerifiedSyntheticArtifact?) { loads.removeFirst().resume(returning: value) }
    func completeDelete() { deletes.removeFirst().resume(returning: ()) }
    private func notify() {
        let ready = waiters.filter { events.count >= $0.0 }
        waiters.removeAll { events.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}
#endif
