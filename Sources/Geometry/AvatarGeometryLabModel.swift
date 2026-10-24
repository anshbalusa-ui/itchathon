#if DEBUG
import Combine
import Foundation

/// UI owner only. The generator actor owns CPU work; this owner admits one
/// physical request and coalesces switches into one latest desired fixture.
@MainActor
final class AvatarGeometryLabModel: ObservableObject {
    enum Failure: Equatable {
        case geometry(GeometryFailure)
        case rendering(RendererFailure)
        case unexpected

        var message: String {
            switch self {
            case .geometry(let error): error.localizedDescription
            case .rendering(let error): error.localizedDescription
            case .unexpected: "Generation could not complete. No surface is displayed. You can retry."
            }
        }
    }

    enum State: Equatable {
        case idle, processing, ready, suspended
        case failed(Failure)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selected: GeometryFixtureID = .surfaceA
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var result: GeometryResult?
    @Published private(set) var orbit = RendererOrbit.initial

    private let generator: any GeometryGenerating
    private let makeScene: @MainActor (GeometryResult) throws -> RendererSceneSession
    private var isPresented = false
    private var isActive = false
    private var generation: UInt64 = 0
    private var workerSequence: UInt64 = 0
    private var activeWorker: UInt64?
    private var worker: Task<Void, Never>?

    init(generator: any GeometryGenerating = SyntheticGeometryGenerator(),
         makeScene: @escaping @MainActor (GeometryResult) throws -> RendererSceneSession = {
             try RendererSceneSession(geometry: $0)
         }) {
        self.generator = generator
        self.makeScene = makeScene
    }

    @discardableResult
    func open(isActive: Bool) -> Task<Void, Never>? {
        isPresented = true
        self.isActive = isActive
        if isActive {
            if state == .idle || state == .suspended { state = .processing }
            startIfPossible()
        } else {
            invalidate()
            state = .suspended
        }
        return worker
    }

    func select(_ fixture: GeometryFixtureID) {
        guard selected != fixture else { return }
        selected = fixture
        orbit.reset()
        generate()
    }

    @discardableResult
    func generate() -> Task<Void, Never>? {
        invalidate()
        guard isPresented, isActive else {
            state = isPresented ? .suspended : .idle
            return worker
        }
        state = .processing
        startIfPossible()
        return worker
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        guard isPresented else { return }
        invalidate()
        state = active ? .processing : .suspended
        startIfPossible()
    }

    func close() {
        isPresented = false
        invalidate()
        selected = .surfaceA
        orbit.reset()
        state = .idle
    }

    func rotate(horizontal: Float, vertical: Float) {
        guard state == .ready else { return }
        orbit.rotate(horizontal: horizontal, vertical: vertical)
        apply()
    }

    func resetView() {
        orbit.reset()
        apply()
    }

    private func apply() {
        session?.apply(orbit: orbit, appearance: RendererAppearance(garmentVisible: false, material: .sage))
    }

    private func invalidate() {
        generation &+= 1
        worker?.cancel()
        // Do NOT clear worker here: cancellation cannot preempt a synchronous
        // calculation. Its acknowledgement opens the single physical slot.
        session?.dispose()
        session = nil
        result = nil
    }

    private func startIfPossible() {
        guard isPresented, isActive, state == .processing, worker == nil else { return }
        workerSequence &+= 1
        let identity = workerSequence
        activeWorker = identity
        let request = generation
        let fixture = selected
        let generator = generator
        worker = Task { [weak self, generator] in
            let outcome: Result<GeometryResult, Error>
            do {
                try Task.checkCancellation()
                outcome = .success(try await generator.generate(fixture))
            } catch {
                outcome = .failure(error)
            }
            self?.finish(identity: identity, request: request, fixture: fixture, outcome: outcome)
        }
    }

    private func finish(identity: UInt64, request: UInt64, fixture: GeometryFixtureID,
                        outcome: Result<GeometryResult, Error>) {
        guard activeWorker == identity else { return }
        worker = nil
        activeWorker = nil
        guard isPresented, isActive else { return }
        guard request == generation, fixture == selected else {
            startIfPossible()
            return
        }
        do {
            let generated = try outcome.get()
            // A producer cannot relabel another fixture's surface as this request.
            guard generated.fixture == fixture else {
                state = .failed(.unexpected)
                return
            }
            let scene = try makeScene(generated)
            scene.onFailure = { [weak self, weak scene] failure in
                guard let self, let scene, self.session === scene else { return }
                self.invalidate()
                self.state = .failed(.rendering(failure))
            }
            result = generated
            session = scene
            apply()
            state = .ready
        } catch let failure as GeometryFailure {
            state = .failed(.geometry(failure))
        } catch is CancellationError {
            state = .failed(.geometry(.cancelled))
        } catch let failure as RendererFailure {
            state = .failed(.rendering(failure))
        } catch {
            state = .failed(.unexpected)
        }
    }
}
#endif
