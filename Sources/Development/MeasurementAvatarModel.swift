#if DEBUG
import Combine
import Foundation

@MainActor
final class MeasurementAvatarModel: ObservableObject, GeometryViewportControlling {
    enum State: Equatable {
        case idle, generating, ready, suspended
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var appearance = RendererAppearance(garmentVisible: false, material: .navy)
    @Published private(set) var orbit = RendererOrbit.initial
    @Published private(set) var generatedInput: MeasurementAvatarInput?
    @Published private(set) var summary = ""

    private let generator: any MeasurementAvatarGenerating
    private var result: MeasurementAvatarResult?
    private var presented = false
    private var active = false
    private var generation: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var requestedInput: MeasurementAvatarInput?

    init(generator: any MeasurementAvatarGenerating = MeasurementAvatarGenerator.shared) {
        self.generator = generator
    }

    var viewportValue: String {
        "Generic measurement-shaped human illustration. Not a scan, exact person, fit result, or size recommendation. Shirt \(appearance.garmentVisible ? "shown" : "hidden")."
    }

    func open(isActive: Bool) {
        presented = true
        active = isActive
        if isActive, let result, session == nil { install(result) }
        else if !isActive { suspend() }
    }

    func close() {
        presented = false
        active = false
        invalidate(clearResult: true)
        state = .idle
        generatedInput = nil
        requestedInput = nil
        summary = ""
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        guard presented else { return }
        if value {
            if let result, session == nil { install(result) }
            else if let input = requestedInput, worker == nil { start(input) }
        } else {
            suspend()
        }
    }

    func generate(_ input: MeasurementAvatarInput) {
        invalidate(clearResult: true)
        requestedInput = input
        generatedInput = nil
        summary = ""
        orbit.reset()
        appearance = RendererAppearance(garmentVisible: false, material: .navy)
        if presented && active { start(input) }
        else { state = .idle }
    }

    /// Editing always clears the previous result before any draft can be generated.
    func editMeasurements() {
        invalidate(clearResult: true)
        requestedInput = nil
        generatedInput = nil
        summary = ""
        state = .idle
        orbit.reset()
    }

    func retry() {
        guard presented, active, let input = requestedInput else { return }
        invalidate(clearResult: true)
        requestedInput = input
        start(input)
    }

    func rotate(horizontal: Float, vertical: Float) {
        guard state == .ready else { return }
        orbit.rotate(horizontal: horizontal, vertical: vertical)
        apply()
    }

    func rotateLeft() { rotate(horizontal: -.pi / 6, vertical: 0) }
    func rotateRight() { rotate(horizontal: .pi / 6, vertical: 0) }

    func resetView() {
        guard state == .ready else { return }
        orbit.reset()
        apply()
    }

    func setShirtVisible(_ visible: Bool) {
        guard state == .ready else { return }
        appearance.garmentVisible = visible
        apply()
    }

    private func start(_ input: MeasurementAvatarInput) {
        guard presented, active, worker == nil else { return }
        state = .generating
        generation &+= 1
        let ticket = generation
        let generator = generator
        worker = Task { [weak self, generator] in
            do {
                let result = try await generator.generate(input)
                try Task.checkCancellation()
                guard let self, self.presented, self.active, self.generation == ticket else { return }
                self.worker = nil
                self.install(result)
            } catch {
                guard !Task.isCancelled, let self, self.presented, self.active, self.generation == ticket else { return }
                self.worker = nil
                self.result = nil
                self.generatedInput = nil
                self.session?.dispose()
                self.session = nil
                self.state = .failed("Avatar generation did not finish. Check the measurements and retry.")
            }
        }
    }

    private func install(_ result: MeasurementAvatarResult) {
        guard presented, active else { return }
        session?.dispose()
        session = nil
        do {
            let scene = try RendererSceneSession(measurementAvatar: result)
            self.result = result
            generatedInput = result.input
            session = scene
            scene.onFailure = { [weak self, weak scene] _ in
                guard let self, let scene, self.session === scene else { return }
                self.invalidate(clearResult: false)
                self.state = .failed("The 3D preview stopped unexpectedly. Retry to rebuild this demonstration.")
            }
            state = .ready
            refreshSummary()
            apply()
        } catch {
            self.result = nil
            generatedInput = nil
            state = .failed("The 3D preview could not be created. Retry to generate it again.")
        }
    }

    private func suspend() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        session?.dispose()
        session = nil
        if result != nil { state = .suspended }
        else if requestedInput != nil { state = .suspended }
    }

    private func invalidate(clearResult: Bool) {
        generation &+= 1
        worker?.cancel()
        worker = nil
        session?.dispose()
        session = nil
        if clearResult {
            result = nil
            generatedInput = nil
        }
    }

    private func apply() {
        guard state == .ready, let session else { return }
        session.apply(orbit: orbit, appearance: appearance)
    }

    private func refreshSummary() {
        guard let input = generatedInput else { summary = ""; return }
        summary = String(format: "Height %.1f cm · chest %.1f cm · waist %.1f cm · hips %.1f cm · shoulder width %.1f cm.", locale: Locale(identifier: "en_US_POSIX"), input.heightCM, input.chestCM, input.waistCM, input.hipsCM, input.shouldersCM)
    }
}
#endif
