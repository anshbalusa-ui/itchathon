#if DEBUG
import Combine
import Foundation

protocol HumanShowcaseLoading: Sendable {
    func load() async throws -> HumanShowcaseMeshes
}

/// One CPU decode shared by visible scenes; no personal profile or scanner dependency.
actor HumanShowcaseAssetStore: HumanShowcaseLoading {
    static let shared = HumanShowcaseAssetStore()
    private var meshes: HumanShowcaseMeshes?

    func load() throws -> HumanShowcaseMeshes {
        if let meshes { return meshes }
        let loaded = try HumanShowcaseAssets.load()
        meshes = loaded
        return loaded
    }
}

@MainActor
final class HumanShowcaseModel: ObservableObject, GeometryViewportControlling {
    enum State: Equatable {
        case idle, loading, ready, suspended
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var session: RendererSceneSession?
    @Published private(set) var appearance: RendererAppearance
    @Published private(set) var orbit = RendererOrbit.initial
    @Published private(set) var region = HumanBodyRegion.whole
    @Published private(set) var fitMapVisible = false
    @Published private(set) var regionSummary = "Whole body · Authored human illustration, not a measured person."
    private let loader: any HumanShowcaseLoading
    private let garment: HumanShowcaseGarment?
    private var meshes: HumanShowcaseMeshes?
    private var presented = false
    private var active = false
    private var generation: UInt64 = 0
    private var worker: Task<Void, Never>?

    init(preview: CatalogIllustrativePreview, loader: any HumanShowcaseLoading = HumanShowcaseAssetStore.shared) {
        self.loader = loader
        let presentation = preview.rendererPresentation
        appearance = RendererAppearance(garmentVisible: true, material: presentation.initialMaterial)
        switch presentation.geometrySource {
        case .procedural: garment = .shirt
        case .bundled(let descriptor): garment = descriptor == .reviewedVest ? .vest : nil
        }
    }

    var viewportValue: String {
        let clothing = appearance.garmentVisible ? "Sample garment shown, \(appearance.material.title)" : "Sample garment hidden"
        return "Authored human model. \(clothing). \(region.title) focus. Sample fit map \(fitMapVisible ? "on" : "off"). Not a personal avatar or verified fit."
    }

    @discardableResult
    func open(isActive: Bool) -> Task<Void, Never>? {
        presented = true
        active = isActive
        if isActive { start() }
        else { invalidate(); state = .suspended }
        return worker
    }

    func close() {
        presented = false
        active = false
        invalidate()
        meshes = nil
        state = .idle
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        guard presented else { return }
        if value { start() }
        else { invalidate(); state = .suspended }
    }

    func retry() {
        guard presented, active else { return }
        invalidate()
        start()
    }

    func rotate(horizontal: Float, vertical: Float) {
        guard state == .ready else { return }
        orbit.rotate(horizontal: horizontal, vertical: vertical)
        apply()
    }

    func resetView() {
        guard state == .ready else { return }
        orbit.reset()
        region = .whole
        refreshSummary()
        apply()
    }

    func focus(_ value: HumanBodyRegion) {
        guard state == .ready else { return }
        region = value
        orbit.reset()
        refreshSummary()
        apply()
    }

    func setGarmentVisible(_ value: Bool) {
        guard state == .ready else { return }
        appearance.garmentVisible = value
        refreshSummary()
        apply()
    }

    func setFitMapVisible(_ value: Bool) {
        guard state == .ready else { return }
        fitMapVisible = value
        refreshSummary()
        apply()
    }

    private func start() {
        guard presented, active, session == nil, worker == nil else { return }
        guard let garment else {
            state = .failed("This sample has no approved human-model clothing illustration. Choose another sample.")
            return
        }
        state = .loading
        generation &+= 1
        let ticket = generation
        let loader = loader
        worker = Task { [weak self, loader] in
            do {
                let meshes = try await loader.load()
                try Task.checkCancellation()
                guard let self, self.presented, self.active, self.generation == ticket else { return }
                let scene = try RendererSceneSession(human: meshes, garment: garment)
                self.meshes = meshes
                self.session = scene
                scene.onFailure = { [weak self, weak scene] _ in
                    guard let self, let scene, self.session === scene else { return }
                    self.invalidate()
                    self.state = .failed("The graphics device could not finish the human preview. Retry to rebuild it.")
                }
                self.worker = nil
                self.state = .ready
                self.refreshSummary()
                self.apply()
            } catch {
                guard !Task.isCancelled, let self, self.generation == ticket, self.presented, self.active else { return }
                self.worker = nil
                self.session?.dispose()
                self.session = nil
                self.meshes = nil
                self.state = .failed("The reviewed human model could not be prepared. Retry to reload its local geometry.")
            }
        }
    }

    private func apply() {
        guard state == .ready, let session else { return }
        do {
            try session.applyHuman(orbit: orbit, appearance: appearance, region: region, mapVisible: fitMapVisible)
        } catch {
            invalidate()
            state = .failed("The selected human view could not be prepared. Retry to rebuild it.")
        }
    }

    private func invalidate() {
        generation &+= 1
        worker?.cancel()
        worker = nil
        session?.dispose()
        session = nil
    }

    private func refreshSummary() {
        guard appearance.garmentVisible else {
            regionSummary = "\(region.title) · Show the sample garment to inspect its spacing."
            return
        }
        guard let meshes, let garment else { return }
        let mesh = garment == .shirt ? meshes.shirt : meshes.vest
        guard let clearance = mesh.sampleClearance else {
            regionSummary = "\(region.title) · No sample clearance data is available."
            return
        }
        let bounds = region.bounds
        var minimum = Float.greatestFiniteMagnitude
        var maximum: Float = 0
        var count = 0
        for index in mesh.vertices.indices {
            let point = mesh.vertices[index].position
            guard point.x >= bounds.minimum.x, point.x <= bounds.maximum.x,
                  point.y >= bounds.minimum.y, point.y <= bounds.maximum.y,
                  point.z >= bounds.minimum.z, point.z <= bounds.maximum.z,
                  region != .arms || abs(point.x) > 0.23 else { continue }
            minimum = min(minimum, clearance[index])
            maximum = max(maximum, clearance[index])
            count += 1
        }
        if count == 0 {
            regionSummary = "\(region.title) · No sample garment covers this region. Not a measured fit result."
        } else {
            let range = String(format: "%.0f–%.0f mm", locale: Locale(identifier: "en_US_POSIX"), minimum * 1000, maximum * 1000)
            regionSummary = "\(region.title) · Sample clearance \(range). Authored surface spacing, not measured fit."
        }
    }
}
#endif
