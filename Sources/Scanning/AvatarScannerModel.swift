#if DEBUG
import Combine
import Foundation

@MainActor
protocol ScanFrameProcessing: AnyObject {
    func process(
        _ input: AppleScanFrameInput,
        generation: UInt64,
        completion: @escaping @MainActor (AppleScanAnalysis?) -> Void
    )
    func releaseRequests()
}

@MainActor
final class AppleScanFrameProcessor: ScanFrameProcessing {
    /// This state is accessed only on queue, never by the main actor.
    private final class WorkerState: @unchecked Sendable {
        var analyzer: AvatarFrameAnalyzer?
        var generation: UInt64?
    }
    private let queue = DispatchQueue(label: "fitcheck.capture.analysis", qos: .userInitiated)
    private let state = WorkerState()

    func process(
        _ input: AppleScanFrameInput,
        generation: UInt64,
        completion: @escaping @MainActor (AppleScanAnalysis?) -> Void
    ) {
        let state = state
        queue.async {
            let result: AppleScanAnalysis? = autoreleasepool {
                if state.generation != generation {
                    state.analyzer = AvatarFrameAnalyzer()
                    state.generation = generation
                }
                do { return try state.analyzer?.analyze(input) }
                catch { return nil } // Translated to retryable quality failure, never success.
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func releaseRequests() {
        let state = state
        queue.async {
            state.analyzer = nil
            state.generation = nil
        }
    }
}

/// Main-actor lifecycle owner. Raw input is owned by at most ONE physical worker
/// job across cancel/retry generations; accepted frames retain depth/mask only.
@MainActor
final class AvatarScannerModel: ObservableObject {
    @Published private(set) var phase: ScanCapturePhase = .idle
    @Published private(set) var guidance: ScanRejection?
    private(set) var evidence: ScanEvidencePair?
    private var coordinator = AvatarCaptureCoordinator()
    private var camera: (any ScanCameraDriving)?
    private let processor: any ScanFrameProcessing
    private let now: () -> Double
    private var analysisBusy = false
    private var front: ScanEvidenceFrame?
    private var timeout: Task<Void, Never>?

    init(processor: (any ScanFrameProcessing)? = nil, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.processor = processor ?? AppleScanFrameProcessor()
        self.now = now
    }

    func attach(_ camera: any ScanCameraDriving) {
        if self.camera != nil { detach() }
        self.camera = camera
        camera.onFrame = { [weak self] input in self?.receive(input) }
        camera.onInterruption = { [weak self] reason in self?.interrupt(reason) }
    }

    func detach() {
        cancel()
        camera?.onFrame = nil
        camera?.onInterruption = nil
        camera = nil
    }

    func start() {
        guard let camera else { return }
        let previousGeneration = coordinator.generation
        let action = coordinator.start(supported: camera.supportsSceneDepth, permission: camera.permission)
        if previousGeneration != coordinator.generation { discardEvidence() }
        syncState()
        switch action {
        case .none: break
        case let .requestPermission(generation):
            camera.requestPermission { [weak self] granted in
                guard let self else { return }
                let shouldRun = self.coordinator.resolvePermission(granted: granted, generation: generation)
                self.syncState()
                if shouldRun { self.runSession(generation: generation) }
            }
        case let .runSession(generation):
            runSession(generation: generation)
        }
    }

    func cancel() {
        coordinator.cancel()
        camera?.pause()
        discardEvidence()
        syncState()
    }

    func suspend() {
        if phase == .candidatePairReady { cancel() }
        else { interrupt(.backgrounded) }
    }

    func interrupt(_ reason: ScanInterruption) {
        switch coordinator.phase {
        case .scanning, .requestingPermission: break
        default: return
        }
        coordinator.interrupt(reason)
        camera?.pause()
        discardEvidence()
        syncState()
    }

    private func runSession(generation: UInt64) {
        guard coordinator.generation == generation, case .scanning = coordinator.phase else { return }
        camera?.run()
        guard coordinator.generation == generation, case .scanning = coordinator.phase else { return }
        timeout?.cancel()
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) }
            catch { return }
            guard let self, self.coordinator.generation == generation else { return }
            self.interrupt(.timedOut)
        }
    }

    private func receive(_ input: AppleScanFrameInput) {
        guard !analysisBusy, let ticket = coordinator.beginFrame(timestamp: input.timestamp, receivedAt: now()) else { return }
        analysisBusy = true
        processor.process(input, generation: ticket.generation) { [weak self] result in
            guard let self else { return }
            // Do not clear this on cancellation: an old Vision job may still run.
            self.analysisBusy = false
            guard self.coordinator.generation == ticket.generation else { return }
            var quality = result?.assessment ?? ScanFrameAssessment(
                timestamp: ticket.timestamp, rejection: .unreliablePose, view: .unverified, anchor: nil
            )
            if quality.rejection == nil,
               (result?.metadata?.timestamp != ticket.timestamp || result?.planes == nil
                || (self.front != nil && result?.metadata?.imageRotation != self.front?.metadata.imageRotation)) {
                quality = ScanFrameAssessment(timestamp: ticket.timestamp, rejection: .invalidAlignment, view: .unverified, anchor: nil)
            }
            let captured = self.coordinator.accept(ticket: ticket, assessment: quality, now: self.now())
            if let captured, let metadata = result?.metadata, let planes = result?.planes {
                let frame = ScanEvidenceFrame(view: captured, metadata: metadata, quality: quality, planes: planes)
                if captured == .front { self.front = frame }
                else if let front = self.front, let pair = ScanEvidencePair(front: front, side: frame) {
                    self.evidence = pair
                    self.front = nil
                    self.timeout?.cancel()
                    self.camera?.pause()
                    self.processor.releaseRequests()
                } else {
                    // A contract violation must never present a captured pair.
                    self.cancel()
                    return
                }
            }
            if case .retryRequired = self.coordinator.phase {
                self.camera?.pause()
                self.discardEvidence()
            }
            self.syncState()
        }
    }

    private func discardEvidence() {
        timeout?.cancel()
        timeout = nil
        front = nil
        evidence = nil
        processor.releaseRequests()
    }

    private func syncState() {
        if phase != coordinator.phase { phase = coordinator.phase }
        if guidance != coordinator.latestRejection { guidance = coordinator.latestRejection }
    }
}
#endif
