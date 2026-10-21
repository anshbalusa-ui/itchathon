#if DEBUG
import Combine
import Foundation

/// Owns one visible, non-AR fixture scene. No profile, scan, or catalog dependency.
@MainActor
final class RendererLabModel: ObservableObject {
    enum State: Equatable {
        case idle
        case ready
        case suspended
        case failed(RendererFailure)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var orbit = RendererOrbit.initial
    @Published private(set) var appearance = RendererAppearance()
    @Published private(set) var garmentFailure: RendererFailure?

    private var isPresented = false
    private var isActive = true
    private let makeScene: @MainActor () throws -> RendererSceneSession

    init(makeScene: (@MainActor () throws -> RendererSceneSession)? = nil) {
        self.makeScene = makeScene ?? { try RendererSceneSession() }
    }

    func open(isActive: Bool) {
        isPresented = true
        self.isActive = isActive
        resumeIfVisible()
    }

    func setActive(_ active: Bool) {
        isActive = active
        guard isPresented else { return }
        if active {
            resumeIfVisible()
        } else {
            releaseScene()
            state = .suspended
        }
    }

    func close() {
        isPresented = false
        releaseScene()
        state = .idle
    }

    func retry() {
        guard isPresented, isActive else { return }
        releaseScene()
        resumeIfVisible()
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

    func setGarmentVisible(_ visible: Bool) {
        appearance.garmentVisible = visible
        apply()
    }

    func selectMaterial(_ material: RendererMaterial) {
        appearance.material = material
        apply()
    }

    func resetAppearance() {
        appearance.reset()
        apply()
    }

    func restoreGarment() {
        guard let session, state == .ready else { return }
        do {
            try session.replaceGarment(asset: .garmentFixture)
            garmentFailure = nil
            apply()
        } catch {
            garmentFailure = (error as? RendererFailure) ?? .sceneCreationFailed
        }
    }

    private func resumeIfVisible() {
        guard isPresented, isActive else {
            state = .suspended
            return
        }
        guard session == nil else { return }
        do {
            let scene = try makeScene()
            scene.apply(orbit: orbit, appearance: appearance)
            session = scene
            scene.onFailure = { [weak self, weak scene] failure in
                guard let self, let scene, self.session === scene else { return }
                self.releaseScene()
                self.state = .failed(failure)
            }
            garmentFailure = scene.garmentFailure
            state = .ready
        } catch {
            state = .failed((error as? RendererFailure) ?? .sceneCreationFailed)
        }
    }

    private func apply() {
        guard state == .ready else { return }
        session?.apply(orbit: orbit, appearance: appearance)
    }

    private func releaseScene() {
        session?.dispose()
        session = nil
        garmentFailure = nil
    }
}
#endif
