#if DEBUG
import MetalKit
import SwiftUI
import UIKit

/// Reuses the renderer's MTKView; only the gesture/accessibility UI owner differs.
struct GeometryViewport: UIViewRepresentable {
    let session: RendererSceneSession
    @ObservedObject var model: AvatarGeometryLabModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> MTKView {
        let view = session.view
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        context.coordinator.panGesture = pan
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "geometry.scene"
        view.accessibilityLabel = "Synthetic surface, interactive 3D scene"
        view.accessibilityHint = "Drag to rotate or use the rotation buttons. Not reconstructed from a person."
        view.accessibilityTraits = .image
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.model = model
        view.accessibilityValue = model.loadedArtifact == nil
            ? "Generated \(model.selected.title)"
            : "Disk-loaded \(model.selected.title)"
    }

    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        if let gesture = coordinator.panGesture { view.removeGestureRecognizer(gesture) }
        coordinator.model = nil
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var model: AvatarGeometryLabModel?
        weak var panGesture: UIPanGestureRecognizer?
        init(model: AvatarGeometryLabModel) { self.model = model }

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
}
#endif
