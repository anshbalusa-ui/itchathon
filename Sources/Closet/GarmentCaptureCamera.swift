@preconcurrency import ARKit
import AVFoundation
import SceneKit
import SwiftUI

struct GarmentCaptureCamera: UIViewControllerRepresentable {
  var onResult: (GarmentCaptureResult) -> Void
  var onGuidance: (String) -> Void

  func makeUIViewController(context: Context) -> GarmentCaptureController {
    let controller = GarmentCaptureController()
    controller.onResult = onResult
    controller.onGuidance = onGuidance
    return controller
  }
  func updateUIViewController(_ controller: GarmentCaptureController, context: Context) {}
  static func dismantleUIViewController(_ controller: GarmentCaptureController, coordinator: ()) { controller.stop() }
}

@MainActor
final class GarmentCaptureController: UIViewController, ARSessionDelegate {
  var onResult: ((GarmentCaptureResult) -> Void)?
  var onGuidance: ((String) -> Void)?
  private var preview: ARSCNView?
  private let analyzer = GarmentDepthAnalyzer()
  private var analysis: Task<Void, Never>?
  private var candidates: [GarmentScanDimensions] = []
  private var lastFrame: TimeInterval = -.infinity
  private var active = false
  private var busy = false

  static var supported: Bool {
    #if targetEnvironment(simulator)
    false
    #else
    ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    #endif
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

  override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black }
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    active = true
    Task { [weak self] in
      let allowed: Bool
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: allowed = true
      case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
      default: allowed = false
      }
      guard let self, active else { return }
      guard allowed else { onGuidance?("Camera access is off. Enable it in Settings, then reopen the scanner."); return }
      guard Self.supported else { onGuidance?("Automatic measurement needs a LiDAR iPhone. You can still add garment photos to your closet."); return }
      let scene = ARSCNView(frame: view.bounds)
      scene.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      scene.isUserInteractionEnabled = false
      scene.session.delegateQueue = .main
      scene.session.delegate = self
      view.addSubview(scene)
      preview = scene
      let config = ARWorldTrackingConfiguration()
      config.frameSemantics = [.sceneDepth]
      scene.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
  }

  override func viewWillDisappear(_ animated: Bool) { stop(); super.viewWillDisappear(animated) }

  func stop() {
    active = false
    analysis?.cancel(); analysis = nil
    preview?.session.delegate = nil
    preview?.session.pause()
    preview?.removeFromSuperview(); preview = nil
    candidates.removeAll(); busy = false
  }

  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    MainActor.assumeIsolated {
      guard active, !busy, session === preview?.session, frame.timestamp - lastFrame > 0.7 else { return }
      guard view.window?.windowScene?.effectiveGeometry.interfaceOrientation == .portrait else {
        candidates.removeAll()
        onGuidance?("Turn your iPhone upright, with the collar toward the top of the screen.")
        return
      }
      busy = true; lastFrame = frame.timestamp
      analysis = Task { [weak self] in
        guard let self else { return }
        defer { busy = false }
        do {
          var result = try await analyzer.analyze(frame)
          guard active, !Task.isCancelled else { return }
          if !candidates.allSatisfy({ $0.agrees(with: result.dimensions) }) { candidates.removeAll() }
          candidates.append(result.dimensions)
          if let dimensions = GarmentScanDimensions.consensus(candidates) {
            result.dimensions = dimensions
            let completion = onResult
            stop()
            completion?(result)
          } else { onGuidance?("Shirt found. Hold still while we check the capture.") }
        } catch {
          guard active, !Task.isCancelled else { return }
          candidates.removeAll()
          onGuidance?(error.localizedDescription)
        }
      }
    }
  }

  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    MainActor.assumeIsolated { stop(); onGuidance?(GarmentCaptureError.interrupted.localizedDescription) }
  }
  nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
    MainActor.assumeIsolated { stop(); onGuidance?("Camera tracking stopped. Close the scanner and try again.") }
  }
}
