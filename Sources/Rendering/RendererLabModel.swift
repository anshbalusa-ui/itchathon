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

    enum AssetState: Equatable {
        case procedural
        case loading
        case loaded
        case failed(RendererAssetLoadFailure)
    }

    @Published private(set) var assetState: AssetState = .procedural

    @Published private(set) var state: State = .idle
    @Published private(set) var session: RendererSceneSession?
    private let assetLoader: any RendererGarmentLoading
    private var requestedBundledAsset = false
    private var assetLoadTask: Task<Void, Never>?
    private var assetRequestGeneration: UInt64 = 0
    private var cachedBundledGarment: RendererLoadedGarment?
    private var requestedBundledDescriptor = RendererBundledAssetDescriptor.reviewedVest
    @Published private(set) var orbit = RendererOrbit.initial
    @Published private(set) var appearance: RendererAppearance
    @Published private(set) var garmentFailure: RendererFailure?

    private var isPresented = false
    private var isActive = true
    private let makeScene: (@MainActor () throws -> RendererSceneSession)?
    let presentation: RendererPresentation
    private let initialMaterial: RendererMaterial

    init(
        presentation: RendererPresentation = .lab,
        assetLoader: any RendererGarmentLoading = RendererBundledAssetLoader(),
        makeScene: (@MainActor () throws -> RendererSceneSession)? = nil
    ) {
        self.presentation = presentation
        self.assetLoader = assetLoader
        self.initialMaterial = presentation.initialMaterial
        self.appearance = RendererAppearance(garmentVisible: true, material: presentation.initialMaterial)
        self.makeScene = makeScene
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
            cancelAssetRequest()
            releaseScene()
            state = .suspended
        }
    }

    func close() {
        isPresented = false
        cancelAssetRequest()
        requestedBundledAsset = false
        requestedBundledDescriptor = .reviewedVest
        cachedBundledGarment = nil
        assetState = .procedural
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
        guard presentation.allowsMaterialChanges || material == initialMaterial else { return }
        appearance.material = material
        apply()
    }

    func resetAppearance() {
        appearance.reset(to: initialMaterial)
        apply()
    }

    func selectProceduralGarment() {
        guard presentation.allowsAssetSelection, isPresented, isActive, state == .ready else { return }
        cancelAssetRequest()
        if !requestedBundledAsset, assetState == .procedural,
           session?.garment != nil, session?.garmentAssetIdentifier == nil { return }
        requestedBundledAsset = false
        requestedBundledDescriptor = .reviewedVest
        cachedBundledGarment = nil
        assetState = .procedural
        guard let session else { return }
        session.clearGarment()
        do {
            try session.replaceGarment(asset: .garmentFixture)
            garmentFailure = nil
            apply()
        } catch {
            garmentFailure = (error as? RendererFailure) ?? .sceneCreationFailed
        }
    }

    @discardableResult
    func selectBundledGarment() -> Task<Void, Never>? {
        guard presentation.allowsAssetSelection, isPresented, isActive, state == .ready else { return nil }
        if requestedBundledAsset, requestedBundledDescriptor == .reviewedVest,
           assetState == .loaded || assetState == .loading { return assetLoadTask }
        requestedBundledAsset = true
        requestedBundledDescriptor = .reviewedVest
        return beginBundledGarmentLoad(requestedBundledDescriptor)
    }

    @discardableResult
    func checkIncompatibleGarment() -> Task<Void, Never>? {
        guard presentation.allowsAssetSelection, isPresented, isActive, state == .ready else { return nil }
        requestedBundledAsset = true
        requestedBundledDescriptor = .incompatibleDemo
        cachedBundledGarment = nil
        return beginBundledGarmentLoad(requestedBundledDescriptor)
    }

    @discardableResult
    func retryGarmentLoad() -> Task<Void, Never>? {
        guard presentation.allowsAssetSelection, isPresented, isActive, state == .ready,
              requestedBundledAsset else { return nil }
        return beginBundledGarmentLoad(requestedBundledDescriptor)
    }

    func restoreGarment() {
        if presentation.allowsAssetSelection {
            selectProceduralGarment()
            return
        }
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
            let scene: RendererSceneSession
            if let makeScene {
                scene = try makeScene()
            } else {
                scene = try RendererSceneSession(garmentAsset: requestedBundledAsset ? nil : .garmentFixture)
            }
            scene.apply(orbit: orbit, appearance: appearance)
            if requestedBundledAsset { scene.clearGarment() }
            session = scene
            scene.onFailure = { [weak self, weak scene] failure in
                guard let self, let scene, self.session === scene else { return }
                self.cancelAssetRequest()
                self.releaseScene()
                self.state = .failed(failure)
            }
            garmentFailure = scene.garmentFailure
            state = .ready
            if requestedBundledAsset {
                if let cachedBundledGarment,
                   cachedBundledGarment.descriptor == requestedBundledDescriptor {
                    do {
                        try scene.installGarment(cachedBundledGarment)
                        assetState = .loaded
                    } catch {
                        assetState = .failed((error as? RendererAssetLoadFailure) ?? .graphicsUnavailable)
                    }
                } else {
                    beginBundledGarmentLoad(requestedBundledDescriptor)
                }
            } else {
                assetState = .procedural
            }
        } catch {
            state = .failed((error as? RendererFailure) ?? .sceneCreationFailed)
        }
    }

    private func cancelAssetRequest() {
        assetRequestGeneration &+= 1
        assetLoadTask?.cancel()
        assetLoadTask = nil
    }

    @discardableResult
    private func beginBundledGarmentLoad(
        _ descriptor: RendererBundledAssetDescriptor = .reviewedVest
    ) -> Task<Void, Never>? {
        cancelAssetRequest()
        cachedBundledGarment = nil
        session?.clearGarment()
        garmentFailure = nil
        assetState = .loading
        let generation = assetRequestGeneration
        guard let sceneID = session?.id else { return nil }
        let loader = assetLoader
        assetLoadTask = Task { [weak self, loader, sceneID, generation] in
            do {
                try Task.checkCancellation()
                let loaded = try await loader.load(descriptor)
                guard !Task.isCancelled, let self,
                      self.assetRequestGeneration == generation,
                      self.isPresented, self.isActive, self.requestedBundledAsset,
                      self.requestedBundledDescriptor == descriptor,
                      self.session?.id == sceneID, self.state == .ready else { return }
                guard loaded.descriptor == descriptor else { throw RendererAssetLoadFailure.unsupportedAsset }
                try self.session?.installGarment(loaded)
                guard self.assetRequestGeneration == generation,
                      self.session?.id == sceneID else { return }
                self.cachedBundledGarment = loaded
                self.assetState = .loaded
                self.garmentFailure = nil
                self.apply()
                self.assetLoadTask = nil
            } catch {
                guard !Task.isCancelled, let self,
                      self.assetRequestGeneration == generation,
                      self.isPresented, self.isActive,
                      self.session?.id == sceneID, self.state == .ready else { return }
                self.session?.clearGarment()
                self.assetState = .failed((error as? RendererAssetLoadFailure) ?? .graphicsUnavailable)
                self.garmentFailure = nil
                self.assetLoadTask = nil
            }
        }
        return assetLoadTask
    }

    private func apply() {
        guard state == .ready else { return }
        session?.apply(orbit: orbit, appearance: appearance)
    }

    private func releaseScene() {
        cancelAssetRequest()
        session?.dispose()
        session = nil
        garmentFailure = nil
    }
}
#endif
