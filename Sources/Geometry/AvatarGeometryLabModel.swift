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
        case artifact(SyntheticArtifactFailure)
        case unexpected

        var message: String {
            switch self {
            case .geometry(let error): error.localizedDescription
            case .rendering(let error): error.localizedDescription
            case .artifact(let error): error.localizedDescription
            case .unexpected: "Generation could not complete. No surface is displayed. You can retry."
            }
        }
    }

    enum State: Equatable {
        case idle, processing, ready, suspended
        case failed(Failure)
    }

    enum ArtifactState: Equatable {
        case idle, loading, missing, deleting, deleted
        case saving(GeometryFixtureID)
        case saved(SyntheticArtifactIdentity)
        case loaded(SyntheticArtifactIdentity)
        case failed(SyntheticArtifactFailure)

        var accessibilityValue: String {
            switch self {
            case .idle: "idle"
            case .loading: "loading"
            case .missing: "missing"
            case .deleting: "deleting"
            case .deleted: "deleted"
            case .saving: "saving"
            case .saved: "saved"
            case .loaded: "loaded"
            case .failed: "failed"
            }
        }
    }

    @Published private(set) var artifactState: ArtifactState = .idle
    @Published private(set) var artifactBusy = false
    @Published private(set) var loadedArtifact: VerifiedSyntheticArtifact?

    var canSaveArtifact: Bool { isPresented && isActive && state == .ready && result != nil && !artifactBusy }
    var canUseArtifactControls: Bool { isPresented && isActive && !artifactBusy }
    var artifactStatus: String {
        switch artifactState {
        case .idle: "No saved artifact has been checked."
        case .loading: "Loading and verifying saved synthetic artifact."
        case .missing: "No saved synthetic artifact exists."
        case .deleting: "Deleting saved synthetic artifact."
        case .deleted: "Saved synthetic artifact deleted."
        case .saving(let fixture): "Saving \(fixture.title)."
        case .saved(let identity): "Saved \(identity.fixture.title)."
        case .loaded(let identity): "Loaded \(identity.fixture.title) from verified saved synthetic artifact."
        case .failed(let failure): failure.localizedDescription
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selected: GeometryFixtureID = .surfaceA
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var result: GeometryResult?
    @Published private(set) var orbit = RendererOrbit.initial

    private let generator: any GeometryGenerating
    private let makeScene: @MainActor (GeometryResult) throws -> RendererSceneSession
    private let artifactStore: any SyntheticArtifactPersisting
    private let makeArtifactScene: @MainActor (VerifiedSyntheticArtifact) throws -> RendererSceneSession
    private var prefersDisk = false
    private var artifactEpoch: UInt64 = 0
    private var artifactSequence: UInt64 = 0
    private var artifactTicket: UInt64?
    private var artifactWorker: Task<Void, Never>?
    private var currentArtifactCommand: ArtifactCommand?
    private var queuedDelete = false
    private var reloadWhenAvailable = false

    private enum ArtifactCommand {
        case save(GeometryResult), load(resetView: Bool), delete
        var isDelete: Bool { if case .delete = self { return true }; return false }
        var isLoad: Bool { if case .load = self { return true }; return false }
    }
    private enum ArtifactOutcome {
        case saved(SyntheticArtifactIdentity), loaded(VerifiedSyntheticArtifact?), deleted
    }
    private var isPresented = false
    private var isActive = false
    private var generation: UInt64 = 0
    private var workerSequence: UInt64 = 0
    private var activeWorker: UInt64?
    private var worker: Task<Void, Never>?

    init(generator: any GeometryGenerating = SyntheticGeometryGenerator(),
         makeScene: @escaping @MainActor (GeometryResult) throws -> RendererSceneSession = {
             try RendererSceneSession(geometry: $0)
         },
         artifactStore: any SyntheticArtifactPersisting = SyntheticArtifactLabStorage.repository(),
         makeArtifactScene: @escaping @MainActor (VerifiedSyntheticArtifact) throws -> RendererSceneSession = {
             try RendererSceneSession(artifact: $0)
         }) {
        self.generator = generator
        self.makeScene = makeScene
        self.artifactStore = artifactStore
        self.makeArtifactScene = makeArtifactScene
    }

    @discardableResult
    func open(isActive: Bool) -> Task<Void, Never>? {
        isPresented = true
        self.isActive = isActive
        if isActive {
            if state == .idle || state == .suspended {
                state = .processing
                if prefersDisk { resumeDiskLoad() } else { startIfPossible() }
            }
        } else {
            cancelArtifactWork(keepDelete: false)
            invalidate()
            state = .suspended
        }
        return prefersDisk ? artifactWorker : worker
    }

    func select(_ fixture: GeometryFixtureID) {
        guard selected != fixture || prefersDisk else { return }
        selected = fixture
        orbit.reset()
        generate()
    }

    @discardableResult
    func generate() -> Task<Void, Never>? {
        prefersDisk = false
        cancelArtifactWork(keepDelete: true)
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
        if !active { cancelArtifactWork(keepDelete: false) }
        state = active ? .processing : .suspended
        if active, prefersDisk { resumeDiskLoad() } else { startIfPossible() }
    }

    func close() {
        isPresented = false
        cancelArtifactWork(keepDelete: false)
        prefersDisk = false
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
        loadedArtifact = nil
    }

    private func startIfPossible() {
        guard isPresented, isActive, !prefersDisk, state == .processing, worker == nil else { return }
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
        guard request == generation, fixture == selected, !prefersDisk else {
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
            configureFailures(of: scene)
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

    @discardableResult
    func saveArtifact() -> Task<Void, Never>? {
        guard canSaveArtifact, let result else { return nil }
        artifactState = .saving(result.fixture)
        return beginArtifact(.save(result))
    }

    @discardableResult
    func loadArtifact(resetView: Bool = true) -> Task<Void, Never>? {
        guard isPresented, isActive, artifactWorker == nil else { return nil }
        prefersDisk = true
        invalidate()
        state = .processing
        artifactState = .loading
        return beginArtifact(.load(resetView: resetView))
    }

    @discardableResult
    func deleteArtifact() -> Task<Void, Never>? {
        guard isPresented, isActive else { return nil }
        prefersDisk = false
        artifactEpoch &+= 1
        reloadWhenAvailable = false
        invalidate()
        state = .idle
        artifactState = .deleting
        if artifactWorker != nil {
            // Do not run deletion alongside a cancellation-ignoring load/save.
            // Selection may proceed, but cannot replace this accepted deletion.
            queuedDelete = true
            artifactWorker?.cancel()
            return nil
        }
        return beginArtifact(.delete)
    }

    private func configureFailures(of scene: RendererSceneSession) {
        scene.onFailure = { [weak self, weak scene] failure in
            guard let self, let scene, self.session === scene else { return }
            self.invalidate()
            self.state = .failed(.rendering(failure))
        }
    }

    private func cancelArtifactWork(keepDelete: Bool) {
        if keepDelete && (queuedDelete || currentArtifactCommand?.isDelete == true) { return }
        artifactEpoch &+= 1
        artifactWorker?.cancel()
        queuedDelete = false
        reloadWhenAvailable = false
        artifactState = .idle
        // Keep the physical worker slot until its actual acknowledgement.
    }

    private func resumeDiskLoad() {
        if artifactWorker == nil { _ = loadArtifact(resetView: false) }
        else { reloadWhenAvailable = true }
    }

    private func beginArtifact(_ command: ArtifactCommand) -> Task<Void, Never> {
        artifactSequence &+= 1
        let ticket = artifactSequence
        artifactTicket = ticket
        let epoch = artifactEpoch
        let display = generation
        let store = artifactStore
        currentArtifactCommand = command
        artifactBusy = true
        let task = Task { [weak self, store] in
            let outcome: Result<ArtifactOutcome, Error>
            do {
                try Task.checkCancellation()
                switch command {
                case .save(let geometry): outcome = .success(.saved(try await store.save(geometry)))
                case .load: outcome = .success(.loaded(try await store.load()))
                case .delete:
                    try await store.delete()
                    outcome = .success(.deleted)
                }
            } catch { outcome = .failure(error) }
            self?.finishArtifact(ticket: ticket, epoch: epoch, display: display, command: command, outcome: outcome)
        }
        artifactWorker = task
        return task
    }

    private func finishArtifact(ticket: UInt64, epoch: UInt64, display: UInt64,
                                command: ArtifactCommand, outcome: Result<ArtifactOutcome, Error>) {
        guard artifactTicket == ticket else { return }
        artifactWorker = nil
        artifactTicket = nil
        currentArtifactCommand = nil
        artifactBusy = false
        if queuedDelete {
            queuedDelete = false
            if isPresented, isActive { _ = beginArtifact(.delete) }
            return
        }
        guard isPresented, isActive, epoch == artifactEpoch,
              command.isDelete || display == generation else {
            if reloadWhenAvailable, isPresented, isActive, prefersDisk {
                reloadWhenAvailable = false
                _ = loadArtifact(resetView: false)
            }
            return
        }
        do {
            switch try outcome.get() {
            case .saved(let identity):
                artifactState = .saved(identity)
            case .deleted:
                artifactState = .deleted
            case .loaded(nil):
                artifactState = .missing
                state = .idle
            case .loaded(let artifact?):
                artifactState = .loaded(artifact.identity)
                let scene = try makeArtifactScene(artifact)
                if case .load(resetView: true) = command { orbit.reset() }
                configureFailures(of: scene)
                selected = artifact.fixture
                loadedArtifact = artifact
                session = scene
                apply()
                state = .ready
            }
        } catch {
            let failure = (error as? SyntheticArtifactFailure)
                ?? (error is CancellationError ? .cancelled : .storageFailure)
            if command.isLoad || (command.isDelete && session == nil) {
                if let rendering = error as? RendererFailure { state = .failed(.rendering(rendering)) }
                else { state = .failed(.artifact(failure)) }
            }
            artifactState = .failed(failure)
        }
    }
}
#endif
