#if DEBUG
import Combine
import XCTest
@testable import FitCheck

@MainActor
final class AvatarGeometryLabModelTests: XCTestCase {
    func testRealGenerationFailureClearsGPUAndValidSelectionRecovers() async throws {
        let model = AvatarGeometryLabModel()
        defer { model.close() }
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.result?.fixture, .surfaceA)
        let oldScene = try XCTUnwrap(model.session)
        let oldObject = oldScene.mannequin
        model.select(.missingRegion)
        XCTAssertNil(model.session)
        XCTAssertNil(model.result)
        XCTAssertTrue(oldScene.isDisposed)
        XCTAssertNil(oldObject.vertexBuffer)
        XCTAssertNil(oldObject.indexBuffer)
        await model.open(isActive: true)?.value
        guard case .failed(.geometry) = model.state else { return XCTFail("Missing evidence must surface a typed failure") }
        XCTAssertNil(model.session)
        XCTAssertNil(model.result)
        model.select(.surfaceB)
        await model.open(isActive: true)?.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.result?.fixture, .surfaceB)
        XCTAssertNotEqual(model.session?.id, oldScene.id)
    }

    func testRapidSwitchesCoalesceUntilPhysicalWorkerAcknowledgesCancellation() async throws {
        let generator = DeferredGeometryGenerator()
        let a = try await SyntheticGeometryGenerator().generate(.surfaceA)
        let b = try await SyntheticGeometryGenerator().generate(.surfaceB)
        let model = AvatarGeometryLabModel(generator: generator)
        defer { model.close() }
        let first = try XCTUnwrap(model.open(isActive: true))
        await generator.waitForCalls(1)
        model.select(.surfaceB)
        model.select(.invalidGeometry)
        model.select(.surfaceA)
        model.select(.surfaceB)
        let before = await generator.fixtures
        XCTAssertEqual(before, [.surfaceA], "Cancellation must not pretend the physical worker is gone")
        XCTAssertNil(model.session)
        await generator.complete(.success(a)) // Deliberately ignores Task cancellation.
        await first.value
        await generator.waitForCalls(2)
        let after = await generator.fixtures
        XCTAssertEqual(after, [.surfaceA, .surfaceB], "Only the latest desired request may be queued")
        XCTAssertEqual(model.state, .processing)
        XCTAssertNil(model.result, "Stale A cannot display under B's title")
        let current = try XCTUnwrap(model.open(isActive: true))
        await generator.complete(.success(b))
        await current.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertEqual(model.result?.fixture, .surfaceB)
    }

    func testDismissDuringGenerationCannotResurrectAndReentryStartsFresh() async throws {
        let generator = DeferredGeometryGenerator()
        let a = try await SyntheticGeometryGenerator().generate(.surfaceA)
        let model = AvatarGeometryLabModel(generator: generator)
        let first = try XCTUnwrap(model.open(isActive: true))
        await generator.waitForCalls(1)
        model.close()
        await generator.complete(.success(a))
        await first.value
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.result)
        XCTAssertNil(model.session)
        let current = try XCTUnwrap(model.open(isActive: true))
        await generator.waitForCalls(2)
        await generator.complete(.success(a))
        await current.value
        let scene = try XCTUnwrap(model.session)
        XCTAssertEqual(model.orbit, .initial)
        model.close()
        XCTAssertNil(scene.mannequin.vertexBuffer)
        XCTAssertNil(scene.mannequin.indexBuffer)
        XCTAssertNil(model.result)
    }

    func testBackgroundClearsGeometryAndOldResultCannotPopulateForeground() async throws {
        let generator = DeferredGeometryGenerator()
        let a = try await SyntheticGeometryGenerator().generate(.surfaceA)
        let model = AvatarGeometryLabModel(generator: generator)
        defer { model.close() }
        let initial = try XCTUnwrap(model.open(isActive: true))
        await generator.waitForCalls(1)
        await generator.complete(.success(a))
        await initial.value
        let scene = try XCTUnwrap(model.session)
        model.rotate(horizontal: 0.6, vertical: 0.1)
        let orbit = model.orbit
        let interrupted = try XCTUnwrap(model.generate())
        await generator.waitForCalls(2)
        model.setActive(false)
        XCTAssertEqual(model.state, .suspended)
        XCTAssertNil(model.session)
        XCTAssertNil(model.result)
        XCTAssertNil(scene.mannequin.vertexBuffer)
        model.setActive(true)
        await generator.complete(.success(a))
        await interrupted.value
        await generator.waitForCalls(3)
        XCTAssertNil(model.session)
        let foreground = try XCTUnwrap(model.open(isActive: true))
        await generator.complete(.success(a))
        await foreground.value
        XCTAssertEqual(model.state, .ready)
        XCTAssertNotEqual(model.session?.id, scene.id)
        XCTAssertEqual(model.orbit, orbit)
    }

    func testRenderFailureClearsCPUAndGPUAndRetryRecreatesScene() async throws {
        let model = AvatarGeometryLabModel()
        defer { model.close() }
        await model.open(isActive: true)?.value
        let oldScene = try XCTUnwrap(model.session)
        let callback = try XCTUnwrap(oldScene.onFailure)
        callback(.graphicsUnavailable)
        XCTAssertEqual(model.state, .failed(.rendering(.graphicsUnavailable)))
        XCTAssertNil(model.result)
        XCTAssertNil(model.session)
        XCTAssertNil(oldScene.mannequin.vertexBuffer)
        await model.generate()?.value
        let replacement = try XCTUnwrap(model.session)
        callback(.sceneCreationFailed)
        XCTAssertTrue(model.session === replacement, "An old scene callback cannot invalidate the replacement")
        XCTAssertEqual(model.state, .ready)
    }

    func testWrongFixtureReplyAndSceneCreationErrorsCannotDisplaySuccess() async throws {
        let generator = DeferredGeometryGenerator()
        let b = try await SyntheticGeometryGenerator().generate(.surfaceB)
        let model = AvatarGeometryLabModel(generator: generator)
        defer { model.close() }
        let request = try XCTUnwrap(model.open(isActive: true))
        await generator.waitForCalls(1)
        await generator.complete(.success(b))
        await request.value
        XCTAssertEqual(model.state, .failed(.unexpected))
        XCTAssertNil(model.session)
        XCTAssertNil(model.result)
        let failing = AvatarGeometryLabModel(makeScene: { _ in throw RendererFailure.graphicsUnavailable })
        defer { failing.close() }
        await failing.open(isActive: true)?.value
        XCTAssertEqual(failing.state, .failed(.rendering(.graphicsUnavailable)))
        XCTAssertNil(failing.result)
        XCTAssertNil(failing.session)
    }

    func testProducerErrorPropagatesAndPendingWorkDoesNotRetainOwner() async throws {
        let generator = DeferredGeometryGenerator()
        var model: AvatarGeometryLabModel? = AvatarGeometryLabModel(generator: generator)
        let request = try XCTUnwrap(model?.open(isActive: true))
        await generator.waitForCalls(1)
        await generator.complete(.failure(GeometryFailure.cancelled))
        await request.value
        XCTAssertEqual(model?.state, .failed(.geometry(.cancelled)))
        let pending = try XCTUnwrap(model?.generate())
        await generator.waitForCalls(2)
        weak var weakModel = model
        model?.close()
        model = nil
        XCTAssertNil(weakModel)
        await generator.complete(.failure(GeometryFailure.cancelled))
        await pending.value
    }
}

/// Ignores cancellation on purpose to exercise late completions and single-flight.
private actor DeferredGeometryGenerator: GeometryGenerating {
    private(set) var fixtures: [GeometryFixtureID] = []
    private var pending: [CheckedContinuation<GeometryResult, Error>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func generate(_ fixture: GeometryFixtureID) async throws -> GeometryResult {
        fixtures.append(fixture)
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = waiters.filter { fixtures.count >= $0.0 }
            waiters.removeAll { fixtures.count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForCalls(_ count: Int) async {
        if fixtures.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func complete(_ result: Result<GeometryResult, Error>) {
        pending.removeFirst().resume(with: result)
    }
}
#endif
