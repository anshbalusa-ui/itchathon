#if DEBUG
import Combine
import Foundation

/// Owns presentation only; simulation/mapping/fitting execute on the service actor.
@MainActor
final class SpatialReplayLabModel: ObservableObject {
    enum Failure: Equatable {
        case replay(ReplayFailure), rendering(RendererFailure), unexpected
        var message: String {
            switch self {
            case .replay(let failure): failure.localizedDescription
            case .rendering(let failure): failure.localizedDescription
            case .unexpected: "Synthetic reconstruction could not complete. No previous surface is displayed."
            }
        }
    }
    enum State: Equatable { case idle, processing, ready, suspended, failed(Failure) }

    @Published private(set) var state: State = .idle
    @Published private(set) var selected: ReplayID = .columnA
    @Published private(set) var result: ReplayGeometryResult?
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var orbit = RendererOrbit.initial

    private let service: any ReplayReconstructing
    private let makeScene: @MainActor (ReplayGeometryResult) throws -> RendererSceneSession
    private var presented = false
    private var active = false
    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var activeWorker: UInt64?
    private var worker: Task<Void, Never>?

    init(service: any ReplayReconstructing = SyntheticReplayReconstructor(),
         makeScene: @escaping @MainActor (ReplayGeometryResult) throws -> RendererSceneSession = {
             try RendererSceneSession(replay: $0)
         }) {
        self.service = service
        self.makeScene = makeScene
    }

    @discardableResult
    func open(isActive: Bool) -> Task<Void, Never>? {
        presented = true
        active = isActive
        if active {
            if state == .idle || state == .suspended { state = .processing }
            startIfPossible()
        } else {
            invalidate()
            state = .suspended
        }
        return worker
    }

    func select(_ replay: ReplayID) {
        guard selected != replay else { return }
        selected = replay
        orbit.reset()
        run()
    }

    @discardableResult
    func run() -> Task<Void, Never>? {
        invalidate()
        guard presented, active else {
            state = presented ? .suspended : .idle
            return worker
        }
        state = .processing
        startIfPossible()
        return worker
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        guard presented else { return }
        invalidate()
        state = active ? .processing : .suspended
        startIfPossible()
    }

    func close() {
        presented = false
        active = false
        invalidate()
        selected = .columnA
        orbit.reset()
        state = .idle
    }

    func rotate(horizontal: Float, vertical: Float) {
        guard state == .ready else { return }
        orbit.rotate(horizontal: horizontal, vertical: vertical)
        apply()
    }

    func resetView() { orbit.reset(); apply() }

    private func apply() {
        session?.apply(orbit: orbit, appearance: RendererAppearance(garmentVisible: false, material: .sage))
    }

    private func invalidate() {
        generation &+= 1
        worker?.cancel()
        // Keep the physical slot until it acknowledges completion; selection
        // changes coalesce into one latest request, never concurrent CPU jobs.
        session?.dispose()
        session = nil
        result = nil
    }

    private func startIfPossible() {
        guard presented, active, state == .processing, worker == nil else { return }
        sequence &+= 1
        let identity = sequence
        activeWorker = identity
        let request = generation
        let replay = selected
        let service = service
        worker = Task { [weak self, service] in
            let outcome: Result<ReplayGeometryResult, Error>
            do {
                try Task.checkCancellation()
                outcome = .success(try await service.reconstruct(replay))
            } catch { outcome = .failure(error) }
            self?.finish(identity: identity, request: request, replay: replay, outcome: outcome)
        }
    }

    private func finish(identity: UInt64, request: UInt64, replay: ReplayID,
                        outcome: Result<ReplayGeometryResult, Error>) {
        guard activeWorker == identity else { return }
        activeWorker = nil
        worker = nil
        guard presented, active else { return }
        guard request == generation, selected == replay else { startIfPossible(); return }
        do {
            let reconstructed = try outcome.get()
            guard reconstructed.id == replay else { state = .failed(.unexpected); return }
            let scene = try makeScene(reconstructed)
            scene.onFailure = { [weak self, weak scene] failure in
                guard let self, let scene, self.session === scene else { return }
                self.invalidate()
                self.state = .failed(.rendering(failure))
            }
            result = reconstructed
            session = scene
            apply()
            state = .ready
        } catch let failure as ReplayFailure { state = .failed(.replay(failure)) }
        catch is CancellationError { state = .failed(.replay(.cancelled)) }
        catch let failure as RendererFailure { state = .failed(.rendering(failure)) }
        catch { state = .failed(.unexpected) }
    }
}
#endif
