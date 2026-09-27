import ARKit
import SceneKit
import UIKit

final class ARMeasurementViewController: UIViewController, ARSessionDelegate {
    var onMeasurement: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?

    private let sceneView = ARSCNView(frame: .zero)
    private var firstPoint: SIMD3<Float>?
    private var markers: [SCNNode] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        let reticle = UILabel()
        reticle.text = "+"
        reticle.textColor = .white
        reticle.font = .systemFont(ofSize: 34, weight: .light)
        reticle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle)
        NSLayoutConstraint.activate([
            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        onStatus?("Move slowly, aim at one edge, then tap.")
    }

    override func viewWillDisappear(_ animated: Bool) {
        sceneView.session.pause()
        super.viewWillDisappear(animated)
    }

    @objc private func tapped() {
        guard let point = centerRaycastPoint() else {
            onStatus?("Could not lock onto the garment surface. Move the phone slightly and try again.")
            return
        }

        if let start = firstPoint {
            let distance = simd_distance(start, point)
            addMarker(at: point)
            onMeasurement?(Double(distance))
            onStatus?(String(format: "Measured %.1f cm. Tap again to start another measurement.", distance * 100))
            firstPoint = nil
        } else {
            clearMarkers()
            firstPoint = point
            addMarker(at: point)
            onStatus?("First point saved. Aim at the opposite edge and tap.")
        }
    }

    private func centerRaycastPoint() -> SIMD3<Float>? {
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)

        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            guard let query = sceneView.raycastQuery(from: center, allowing: target, alignment: .any) else {
                continue
            }

            if let hit = sceneView.session.raycast(query).first {
                let t = hit.worldTransform.columns.3
                return SIMD3<Float>(t.x, t.y, t.z)
            }
        }

        return nil
    }

    private func addMarker(at point: SIMD3<Float>) {
        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.systemYellow
        let node = SCNNode(geometry: sphere)
        node.simdPosition = point
        sceneView.scene.rootNode.addChildNode(node)
        markers.append(node)
    }

    private func clearMarkers() {
        markers.forEach { $0.removeFromParentNode() }
        markers.removeAll()
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .normal:
            break
        case .notAvailable:
            onStatus?("AR tracking is unavailable.")
        case .limited(.excessiveMotion):
            onStatus?("Slow down for a more stable measurement.")
        case .limited(.insufficientFeatures):
            onStatus?("Aim at a better-lit or more textured area.")
        case .limited(.initializing):
            onStatus?("Initializing AR…")
        case .limited(.relocalizing):
            onStatus?("Relocalizing…")
        @unknown default:
            break
        }
    }
}
