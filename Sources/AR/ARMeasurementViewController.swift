import ARKit
import AVFoundation
import SceneKit
import UIKit

final class ARMeasurementViewController: UIViewController, ARSessionDelegate {
    var onMeasurement: ((Double) -> Void)?
    var onStatus: ((String) -> Void)?

    private let sceneView = ARSCNView(frame: .zero)
    private var firstPoint: SIMD3<Float>?

    var onReset: (() -> Void)?

    private var markerA: SCNNode?
    private var markerB: SCNNode?
    private var measurementLine: SCNNode?
    private var pendingDistance: Double?
    private var isVisible = false
    private var isSessionRunning = false
    private var hasStartedSession = false
    private var isTrackingNormally = false
    private var permissionRequestInFlight = false

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

        sceneView.session.delegateQueue = .main
        sceneView.session.delegate = self
        sceneView.automaticallyUpdatesLighting = true
        sceneView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))

        let reticle = UILabel()
        reticle.text = "+"
        reticle.textColor = .white
        reticle.font = .systemFont(ofSize: 34, weight: .light)
        reticle.textAlignment = .center
        reticle.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        reticle.layer.cornerRadius = 21
        reticle.clipsToBounds = true
        reticle.accessibilityLabel = "Center reticle. Tap the screen to place a measurement point."
        reticle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reticle)
        NSLayoutConstraint.activate([
            reticle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            reticle.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            reticle.widthAnchor.constraint(equalToConstant: 42),
            reticle.heightAnchor.constraint(equalToConstant: 42)
        ])
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive(_:)),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        prepareCameraAndStartSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        isVisible = false
        pauseSession(clearCapture: true)
        hasStartedSession = false
        super.viewWillDisappear(animated)
    }

    private func prepareCameraAndStartSession() {
        guard isVisible else { return }
        guard ARWorldTrackingConfiguration.isSupported else {
            pauseSession(clearCapture: true)
            onStatus?("AR world tracking is unavailable on this device.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession(resetTracking: !hasStartedSession)
        case .notDetermined:
            guard !permissionRequestInFlight else { return }
            permissionRequestInFlight = true
            onStatus?("Camera permission is required to measure the shirt.")
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionRequestInFlight = false
                    guard self.isVisible else { return }
                    guard granted else {
                        self.cameraAccessUnavailable()
                        return
                    }
                    self.startSession(resetTracking: !self.hasStartedSession)
                }
            }
        case .denied, .restricted:
            cameraAccessUnavailable()
        @unknown default:
            cameraAccessUnavailable()
        }
    }

    private func startSession(resetTracking: Bool) {
        guard isVisible, UIApplication.shared.applicationState == .active, !isSessionRunning else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            cameraAccessUnavailable()
            return
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        let options: ARSession.RunOptions = resetTracking ? [.resetTracking, .removeExistingAnchors] : []

        isSessionRunning = true
        hasStartedSession = true
        isTrackingNormally = false
        sceneView.session.run(configuration, options: options)
        onStatus?("Lay the shirt flat on a horizontal surface. Starting AR tracking…")
    }

    private func cameraAccessUnavailable() {
        pauseSession(clearCapture: true)
        hasStartedSession = false
        onStatus?("Camera access is off. Allow camera access in Settings to measure the shirt.")
    }

    private func pauseSession(clearCapture: Bool) {
        sceneView.session.pause()
        isSessionRunning = false
        isTrackingNormally = false
        if clearCapture {
            clearMeasurement(notify: true)
        }
    }

    @objc private func applicationWillResignActive(_ notification: Notification) {
        guard isVisible else { return }
        pauseSession(clearCapture: true)
        onStatus?("Camera paused. Resume to start again at point A.")
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard isVisible else { return }
        prepareCameraAndStartSession()
    }

    @objc private func tapped() {
        guard isSessionRunning, isTrackingNormally else {
            onStatus?("Wait for normal AR tracking before placing a point.")
            return
        }
        guard pendingDistance == nil else { return }
        guard let point = centerRaycastPoint() else {
            onStatus?("No horizontal surface under the center reticle. Move the phone slightly and try again.")
            return
        }

        if let start = firstPoint {
            let distance = simd_distance(start, point)
            guard distance.isFinite, distance > 0,
                  let line = makeMeasurementLine(from: start, to: point) else {
                onStatus?("Those points could not form a valid measurement. Reset and try again.")
                return
            }

            markerB = addMarker(at: point, label: "B", color: .systemOrange)
            measurementLine = line
            pendingDistance = Double(distance)
            onMeasurement?(Double(distance))
            onStatus?(String(format: "A to B is %.1f cm. Use Measurement to confirm or Reset to discard.", distance * 100))
        } else {
            firstPoint = point
            markerA = addMarker(at: point, label: "A", color: .systemGreen)
            onStatus?("Point A saved. Aim the center reticle at the opposite edge B, then tap the screen.")
        }
    }

    private func centerRaycastPoint() -> SIMD3<Float>? {
        guard sceneView.bounds.width > 0, sceneView.bounds.height > 0 else { return nil }
        let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)

        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            guard let query = sceneView.raycastQuery(from: center, allowing: target, alignment: .horizontal) else {
                continue
            }

            if let hit = sceneView.session.raycast(query).first {
                let t = hit.worldTransform.columns.3
                return SIMD3<Float>(t.x, t.y, t.z)
            }
        }

        return nil
    }

    private func addMarker(at point: SIMD3<Float>, label: String, color: UIColor) -> SCNNode {
        let marker = SCNNode()
        marker.simdPosition = point

        let sphere = SCNSphere(radius: 0.005)
        sphere.firstMaterial?.diffuse.contents = color
        marker.addChildNode(SCNNode(geometry: sphere))

        let textGeometry = SCNText(string: label, extrusionDepth: 0.001)
        textGeometry.font = .boldSystemFont(ofSize: 1)
        textGeometry.firstMaterial?.diffuse.contents = color
        let textNode = SCNNode(geometry: textGeometry)
        textNode.simdScale = SIMD3<Float>(repeating: 0.018)
        textNode.simdPosition = SIMD3<Float>(-0.006, 0.01, 0)
        textNode.constraints = [SCNBillboardConstraint()]
        marker.addChildNode(textNode)

        sceneView.scene.rootNode.addChildNode(marker)
        return marker
    }

    private func makeMeasurementLine(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SCNNode? {
        let direction = end - start
        let distance = simd_length(direction)
        guard distance.isFinite, distance > 0 else { return nil }

        let geometry = SCNCylinder(radius: 0.002, height: CGFloat(distance))
        geometry.firstMaterial?.diffuse.contents = UIColor.systemYellow
        let line = SCNNode(geometry: geometry)
        line.simdPosition = (start + end) / 2
        line.simdOrientation = simd_quatf(
            from: SIMD3<Float>(0, 1, 0),
            to: direction / distance
        )
        sceneView.scene.rootNode.addChildNode(line)
        return line
    }

    func resetMeasurement() {
        clearMeasurement(notify: false)
    }

    private func clearMeasurement(notify: Bool) {
        let hadCapture = firstPoint != nil || pendingDistance != nil
        firstPoint = nil
        pendingDistance = nil
        markerA?.removeFromParentNode()
        markerA = nil
        markerB?.removeFromParentNode()
        markerB = nil
        measurementLine?.removeFromParentNode()
        measurementLine = nil
        if notify, hadCapture {
            onReset?()
        }
    }

    private func updateLimitedTracking(status: String) {
        isTrackingNormally = false
        if firstPoint != nil, pendingDistance == nil {
            clearMeasurement(notify: true)
        }
        onStatus?(status)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guard isVisible, isSessionRunning else { return }
        switch camera.trackingState {
        case .normal:
            guard !isTrackingNormally else { return }
            isTrackingNormally = true
            if let pendingDistance {
                onStatus?(String(format: "A to B is %.1f cm. Use Measurement to confirm or Reset to discard.", pendingDistance * 100))
                return
            }
            onStatus?(firstPoint == nil
                ? "Tracking normal. Aim the center reticle at point A, then tap the screen."
                : "Tracking normal. Aim the center reticle at the opposite edge B, then tap the screen.")
        case .notAvailable:
            updateLimitedTracking(status: "AR tracking is unavailable.")
        case .limited(.excessiveMotion):
            updateLimitedTracking(status: "Slow down and hold the phone steady.")
        case .limited(.insufficientFeatures):
            updateLimitedTracking(status: "Aim at a well-lit, textured area.")
        case .limited(.initializing):
            updateLimitedTracking(status: "Initializing AR tracking…")
        case .limited(.relocalizing):
            updateLimitedTracking(status: "Relocalizing. Point A was cleared; begin again when tracking is normal.")
        @unknown default:
            updateLimitedTracking(status: "AR tracking is limited. Wait before placing a point.")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        guard isVisible else { return }
        pauseSession(clearCapture: true)
        onStatus?("AR session interrupted. Measurement points were cleared; wait for tracking to resume.")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        guard isVisible else { return }
        prepareCameraAndStartSession()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        guard isVisible else { return }
        pauseSession(clearCapture: true)
        hasStartedSession = false
        onStatus?("AR camera stopped: \(error.localizedDescription)")
    }
}
