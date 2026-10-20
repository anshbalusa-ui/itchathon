import ARKit
import AVFoundation
import SceneKit
import SwiftUI
import UIKit

/// Experimental avatar capture, intentionally separate from the existing
/// manually marked body-measurement scanner.
final class AvatarGuidedCaptureController: UIViewController, ARSessionDelegate {
    var onComplete: ((AvatarScanCapture) -> Void)?
    var onCancel: (() -> Void)?

    private let sceneView = ARSCNView()
    private let instructionLabel = UILabel()
    private let detailLabel = UILabel()
    private let sessionQueue = DispatchQueue(label: "fitcheck.avatar.session")
    private let visionQueue = DispatchQueue(label: "fitcheck.avatar.vision", qos: .userInitiated)
    private let detector = AvatarPersonDetector()

    // State is confined to sessionQueue, except UI work dispatched to main.
    private var coordinator = AvatarCaptureCoordinator()
    private var processingFrame = false
    private var lastProcessedTime: TimeInterval = -.infinity
    private var lastCenter: CGPoint?
    private var frontSnapshot: AvatarScanSnapshot?
    private var ended = false

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.automaticallyUpdatesLighting = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let guidance = UIStackView()
        guidance.axis = .vertical
        guidance.spacing = 8
        guidance.alignment = .fill
        guidance.translatesAutoresizingMaskIntoConstraints = false
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        background.translatesAutoresizingMaskIntoConstraints = false
        background.layer.cornerRadius = 16
        background.clipsToBounds = true
        view.addSubview(background)
        background.contentView.addSubview(guidance)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            guidance.topAnchor.constraint(equalTo: background.contentView.topAnchor, constant: 18),
            guidance.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor, constant: -18),
            guidance.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 18),
            guidance.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -18)
        ])
        instructionLabel.font = .preferredFont(forTextStyle: .title3)
        instructionLabel.textColor = .white
        instructionLabel.numberOfLines = 0
        instructionLabel.text = "Stand facing the camera"
        detailLabel.font = .preferredFont(forTextStyle: .body)
        detailLabel.textColor = .white
        detailLabel.numberOfLines = 0
        detailLabel.text = "Keep your full body in view. Hold still while the camera finds you."
        guidance.addArrangedSubview(instructionLabel)
        guidance.addArrangedSubview(detailLabel)

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.configuration = .filled()
        cancel.configuration?.title = "Cancel scan"
        cancel.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
        sceneView.session.delegate = self
        sceneView.session.delegateQueue = sessionQueue
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestCameraAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    private func requestCameraAndStart() {
        guard ARWorldTrackingConfiguration.isSupported,
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            showIssue("This scan needs an iPhone Pro with LiDAR.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    if allowed { self?.startSession() }
                    else { self?.showIssue("Allow camera access to create an avatar.") }
                }
            }
        default:
            showIssue("Allow camera access in Settings to use the scanner.")
        }
    }

    private func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics.insert(.sceneDepth)
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    private func showIssue(_ message: String) {
        instructionLabel.text = "Unable to scan"
        detailLabel.text = message
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard !ended, !processingFrame,
              frame.timestamp - lastProcessedTime >= 0.35 else { return }
        processingFrame = true
        lastProcessedTime = frame.timestamp

        visionQueue.async { [weak self] in
            guard let self else { return }
            let result = try? self.detector.analyze(frame.capturedImage)
            let depth = frame.sceneDepth
            let depthUsable = depth.map(AvatarDepthInspector.hasUsableDepth) ?? false
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.processingFrame = false
                self.accept(frame: frame, person: result, depth: depth, depthUsable: depthUsable)
            }
        }
    }

    private func accept(frame: ARFrame, person: AvatarPersonObservation?,
                        depth: ARDepthData?, depthUsable: Bool) {
        guard !ended else { return }

        let stable: Bool
        if let current = person?.torsoCenter, let previous = lastCenter {
            stable = hypot(current.x - previous.x, current.y - previous.y) < 0.035
        } else {
            stable = false
        }
        lastCenter = person?.torsoCenter

        let readiness = AvatarFrameReadiness(
            fullPersonVisible: person?.fullPersonVisible ?? false,
            poseReliable: person?.poseReliable ?? false,
            depthUsable: depthUsable,
            stable: stable
        )
        guard let captured = coordinator.accept(readiness) else {
            if !readiness.canCapture {
                let detail: String
                if person?.fullPersonVisible != true {
                    detail = "Move back so your whole body is visible."
                } else if !depthUsable {
                    detail = "Move into better light and hold the phone steady."
                } else {
                    detail = "Hold still for the camera."
                }
                DispatchQueue.main.async { [weak self] in self?.detailLabel.text = detail }
            }
            return
        }

        guard let person, let depth, let confidence = depth.confidenceMap else {
            coordinator.reset()
            frontSnapshot = nil
            return
        }

        let snapshot = AvatarScanSnapshot(
            cameraImage: frame.capturedImage,
            depthMap: depth.depthMap,
            confidenceMap: confidence,
            personMask: person.mask,
            cameraIntrinsics: frame.camera.intrinsics,
            cameraResolution: frame.camera.imageResolution,
            timestamp: frame.timestamp,
            landmarks: person.landmarks,
            angle: captured
        )
        lastCenter = nil
        if captured == .front {
            frontSnapshot = snapshot
            DispatchQueue.main.async { [weak self] in
                self?.instructionLabel.text = "Now turn sideways"
                self?.detailLabel.text = "Keep your full body in view and stand still again."
            }
        } else if let front = frontSnapshot {
            ended = true
            sessionQueueCleanup()
            let bundle = AvatarScanCapture(front: front, side: snapshot)
            DispatchQueue.main.async { [weak self] in self?.onComplete?(bundle) }
        }
    }

    private func sessionQueueCleanup() {
        // Called on sessionQueue; buffers remain alive only in the returned bundle.
        frontSnapshot = nil
        DispatchQueue.main.async { [weak self] in
            self?.sceneView.session.pause()
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.showIssue("Camera tracking was interrupted. Close the scan and try again.")
        }
    }

    func stopScanning() {
        sceneView.session.pause()
        sessionQueue.async { [weak self] in
            self?.ended = true
            self?.coordinator.cancel()
            self?.frontSnapshot = nil
            self?.lastCenter = nil
        }
    }

    @objc private func cancelScan() {
        stopScanning()
        onCancel?()
    }
}

struct AvatarGuidedCaptureView: UIViewControllerRepresentable {
    var onComplete: (AvatarScanCapture) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> AvatarGuidedCaptureController {
        let controller = AvatarGuidedCaptureController()
        controller.onComplete = onComplete
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ controller: AvatarGuidedCaptureController, context: Context) {
        controller.onComplete = onComplete
        controller.onCancel = onCancel
    }

    static func dismantleUIViewController(_ controller: AvatarGuidedCaptureController,
                                           coordinator: ()) {
        controller.stopScanning()
    }
}

/// First-stage scanner test screen; capture buffers are never persisted.
struct CreateAvatarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var capture: AvatarScanCapture?
    @State private var captureIdentity = UUID()

    var body: some View {
        Group {
            if capture != nil {
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Scan captured")
                        .font(.title.bold())
                    Text("Your front and side views were captured. Creating your 3D avatar is the next development step.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        capture = nil
                        captureIdentity = UUID()
                    }
                    Button("Done") {
                        capture = nil
                        dismiss()
                    }
                }
                .padding(24)
            } else {
                AvatarGuidedCaptureView(
                    onComplete: { result in capture = result },
                    onCancel: { dismiss() }
                )
                .id(captureIdentity)
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("Create your avatar")
        .navigationBarTitleDisplayMode(.inline)
    }
}
