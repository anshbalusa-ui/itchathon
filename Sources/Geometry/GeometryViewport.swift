#if DEBUG
import MetalKit
import SwiftUI
import UIKit

@MainActor
protocol GeometryViewportControlling: ObservableObject {
    var viewportValue: String { get }
    func rotate(horizontal: Float, vertical: Float)
}

/// Both synthetic labs use the same MTKView, gestures and dismantle ownership.
struct GeometryViewport<Model: GeometryViewportControlling>: UIViewRepresentable {
    let session: RendererSceneSession
    @ObservedObject var model: Model
    var sceneIdentifier = "geometry.scene"
    var sceneLabel = "Synthetic surface, interactive 3D scene"
    var sceneHint = "Drag to rotate or use the rotation buttons. Not reconstructed from a person."

    func makeCoordinator() -> GeometryViewportCoordinator { GeometryViewportCoordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = session.view
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(GeometryViewportCoordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.panGesture = pan
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = sceneIdentifier
        view.accessibilityLabel = sceneLabel
        view.accessibilityHint = sceneHint
        view.accessibilityTraits = .image
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.model = model
        view.accessibilityValue = model.viewportValue
    }

    static func dismantleUIView(_ view: MTKView, coordinator: GeometryViewportCoordinator) {
        if let gesture = coordinator.panGesture { view.removeGestureRecognizer(gesture) }
        coordinator.model = nil
    }
}

@MainActor
final class GeometryViewportCoordinator: NSObject {
    weak var model: (any GeometryViewportControlling)?
    weak var panGesture: UIPanGestureRecognizer?
    init(model: any GeometryViewportControlling) { self.model = model }

    @objc func pan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .changed else {
            recognizer.setTranslation(.zero, in: recognizer.view)
            return
        }
        let delta = recognizer.translation(in: recognizer.view)
        recognizer.setTranslation(.zero, in: recognizer.view)
        model?.rotate(horizontal: Float(delta.x) * 0.008, vertical: Float(delta.y) * 0.006)
    }
}

extension AvatarGeometryLabModel: GeometryViewportControlling {
    var viewportValue: String {
        loadedArtifact == nil ? "Generated \(selected.title)" : "Disk-loaded \(selected.title)"
    }
}
#endif
