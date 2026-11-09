#if DEBUG
import XCTest
@testable import FitCheck

@MainActor
final class MeasurementAvatarModelTests: XCTestCase {
    func testGenerationCreatesRealSceneAndEditImmediatelyRemovesGeneratedResult() async throws {
        let input = MeasurementAvatarInput.sampleB
        let model = MeasurementAvatarModel()
        model.open(isActive: true)
        model.generate(input)
        await waitUntil { model.state == .ready }

        let first = try XCTUnwrap(model.session)
        XCTAssertEqual(model.generatedInput, input)
        model.rotateRight()
        XCTAssertNotEqual(model.orbit, .initial)
        model.setShirtVisible(false)
        XCTAssertEqual(first.mannequin.mesh.maximum.y - first.mannequin.mesh.minimum.y,
                       Float(input.heightCM / 100), accuracy: 0.001,
                       "The visible scene must use the generated dimensions, not the 1.8 m template")
        XCTAssertFalse(model.appearance.garmentVisible)

        model.editMeasurements()
        XCTAssertNil(model.session)
        XCTAssertNil(model.generatedInput)
        XCTAssertTrue(model.summary.isEmpty)
        XCTAssertTrue(first.isDisposed)
        XCTAssertEqual(model.state, .idle)
        model.close()
    }

    func testForegroundRebuildUsesCurrentResultAndDismissalDisposesScene() async throws {
        let input = try MeasurementAvatarInput(heightCM: 170, chestCM: 110, waistCM: 100, hipsCM: 112, shouldersCM: 48)
        let model = MeasurementAvatarModel()
        model.open(isActive: true)
        model.generate(input)
        await waitUntil { model.state == .ready }
        let first = try XCTUnwrap(model.session)
        model.setActive(false)
        XCTAssertNil(model.session)
        XCTAssertTrue(first.isDisposed)
        XCTAssertEqual(model.state, .suspended)

        model.setActive(true)
        let rebuilt = try await waitForSession(model)
        XCTAssertNotEqual(first.id, rebuilt.id)
        XCTAssertEqual(model.generatedInput, input)
        XCTAssertEqual(model.state, .ready)
        model.close()
        XCTAssertTrue(rebuilt.isDisposed)
        XCTAssertNil(model.session)
    }

    func testFailureHasNoStaleResultAndRetryRecoversWithRealGeometry() async throws {
        let generator = RecoveringMeasurementAvatarGenerator()
        let input = try MeasurementAvatarInput(heightCM: 180, chestCM: 96, waistCM: 80, hipsCM: 98, shouldersCM: 43)
        let model = MeasurementAvatarModel(generator: generator)
        model.open(isActive: true)
        model.generate(input)
        await waitUntil { if case .failed = model.state { return true }; return false }
        XCTAssertNil(model.session)
        XCTAssertNil(model.generatedInput)
        XCTAssertTrue(model.summary.isEmpty)

        model.retry()
        await waitUntil { model.state == .ready }
        XCTAssertNotNil(model.session)
        XCTAssertEqual(model.generatedInput, input)
        model.close()
    }

    func testGenerateThenEditInvalidatesPendingCompletion() async throws {
        let generated = try await MeasurementAvatarGenerator.shared.generate(.sampleA)
        let generator = DeferredMeasurementAvatarGenerator(result: generated)
        let model = MeasurementAvatarModel(generator: generator)
        model.open(isActive: true)
        model.generate(.sampleA)
        await generator.waitUntilStarted()
        model.editMeasurements()
        await generator.release()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.session)
        XCTAssertNil(model.generatedInput)
        model.close()
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for measurement avatar state")
    }

    private func waitForSession(_ model: MeasurementAvatarModel) async throws -> RendererSceneSession {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if let session = model.session, model.state == .ready { return session }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "MeasurementAvatarModelTests", code: 1)
    }
}

private actor RecoveringMeasurementAvatarGenerator: MeasurementAvatarGenerating {
    private var failed = false
    func generate(_ input: MeasurementAvatarInput) async throws -> MeasurementAvatarResult {
        if !failed {
            failed = true
            throw NSError(domain: "MeasurementAvatarModelTests", code: 2)
        }
        return try await MeasurementAvatarGenerator.shared.generate(input)
    }
}

private actor DeferredMeasurementAvatarGenerator: MeasurementAvatarGenerating {
    private let result: MeasurementAvatarResult
    private var continuation: CheckedContinuation<MeasurementAvatarResult, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(result: MeasurementAvatarResult) { self.result = result }

    func generate(_ input: MeasurementAvatarInput) async throws -> MeasurementAvatarResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func release() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
#endif
