#if DEBUG
@preconcurrency import ARKit
import AVFoundation
import SceneKit
import UIKit

@MainActor
protocol ScanCameraDriving: AnyObject {
    var supportsSceneDepth: Bool { get }
    var permission: ScanCameraPermission { get }
    var onFrame: ((AppleScanFrameInput) -> Void)? { get set }
    var onInterruption: ((ScanInterruption) -> Void)? { get set }
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void)
    func run()
    func pause()
}

/// Apple-only preview/session ownership. Delegate delivery is explicitly main;
/// Vision and pixel inspection never execute here. No preview exists before consent.
@MainActor
final class AvatarGuidedCaptureController: UIViewController, ScanCameraDriving, ARSessionDelegate {
    var onFrame: ((AppleScanFrameInput) -> Void)?
    var onInterruption: ((ScanInterruption) -> Void)?
    var onReady: (() -> Void)?
    var onDisappear: (() -> Void)?
    private var preview: ARSCNView?
    private var visible = false
    private var lastDeliveredAt: TimeInterval = -.infinity

    var supportsSceneDepth: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #endif
    }

    var permission: ScanCameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        default: return .denied
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        // Only the first appearance belongs to the explicit introduction start.
        // Later appearances must not implicitly resume an interrupted attempt.
        let ready = onReady
        onReady = nil
        ready?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        visible = false
        onDisappear?()
        pause()
        super.viewWillDisappear(animated)
    }

    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted) }
        }
    }

    func run() {
        guard visible, preview == nil, supportsSceneDepth, permission == .authorized else { return }
        guard view.window?.windowScene?.interfaceOrientation == .portrait else {
            onInterruption?(.orientationChanged)
            return
        }
        let scene = ARSCNView(frame: view.bounds)
        scene.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scene.isUserInteractionEnabled = false
        scene.automaticallyUpdatesLighting = false
        scene.session.delegateQueue = .main
        scene.session.delegate = self
        view.addSubview(scene)
        preview = scene
        lastDeliveredAt = -.infinity
        let configuration = ARWorldTrackingConfiguration()
        configuration.frameSemantics = [.sceneDepth]
        configuration.planeDetection = []
        scene.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func pause() {
        guard let scene = preview else { return }
        scene.session.delegate = nil
        scene.session.pause()
        scene.removeFromSuperview()
        // Release ARSession.currentFrame and renderer camera textures, not just
        // application references. An in-flight analysis may still own one input.
        preview = nil
    }

    func shutdown() {
        pause()
        onFrame = nil
        onInterruption = nil
        onReady = nil
        onDisappear = nil
    }

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated {
            guard let scene = preview, session === scene.session,
                  frame.timestamp.isFinite, frame.timestamp >= 0,
                  frame.timestamp - lastDeliveredAt >= 0.25 else { return }
            // Compare only timestamps from this ARSession, never an assumed epoch.
            if let newest = session.currentFrame, newest.timestamp - frame.timestamp > 0.25 { return }
            guard view.window?.windowScene?.interfaceOrientation == .portrait else {
                onInterruption?(.orientationChanged)
                return
            }
            lastDeliveredAt = frame.timestamp
            let image = frame.capturedImage
            guard Int(frame.camera.imageResolution.width) == CVPixelBufferGetWidth(image),
                  Int(frame.camera.imageResolution.height) == CVPixelBufferGetHeight(image) else {
                onInterruption?(.trackingFailed)
                return
            }
            let matrix = frame.camera.transform
            let intrinsics = frame.camera.intrinsics
            let trackingNormal: Bool
            if case .normal = frame.camera.trackingState { trackingNormal = true }
            else { trackingNormal = false }
            onFrame?(AppleScanFrameInput(
                timestamp: frame.timestamp,
                image: image,
                depth: frame.sceneDepth?.depthMap,
                confidence: frame.sceneDepth?.confidenceMap,
                imageRotation: .right,
                calibration: ScanCameraCalibration(
                    fx: Double(intrinsics[0][0]), fy: Double(intrinsics[1][1]),
                    cx: Double(intrinsics[2][0]), cy: Double(intrinsics[2][1])
                ),
                cameraPosition: ScanVector(x: Double(matrix[3].x), y: Double(matrix[3].y), z: Double(matrix[3].z)),
                cameraForward: ScanVector(x: -Double(matrix[2].x), y: -Double(matrix[2].y), z: -Double(matrix[2].z)),
                trackingNormal: trackingNormal
            ))
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            guard session === preview?.session else { return }
            onInterruption?(.sessionInterrupted)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            guard session === preview?.session else { return }
            onInterruption?(.trackingFailed)
        }
    }
}
#endif
