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

/// Bounds analysis to one frame and makes completion/defer ownership explicit across camera restarts.
struct GarmentCaptureScheduler {
  /// Keep the existing cap until physical-device inference measurements justify changing it.
  static let minimumFrameInterval: TimeInterval = 0.7
  struct Ticket: Equatable {
    fileprivate var generation: UInt64
    fileprivate var frame: UInt64
    var timestamp: TimeInterval
  }

  private(set) var generation: UInt64 = 0
  private(set) var lastAnalysisDuration: TimeInterval?
  private var active = false
  private var inFlight: Ticket?
  private var nextFrame: UInt64 = 0
  private var lastTimestamp: TimeInterval = -.infinity

  mutating func start() {
    generation &+= 1
    active = true
    inFlight = nil
    lastTimestamp = -.infinity
  }

  mutating func stop() {
    generation &+= 1
    active = false
    inFlight = nil
    lastTimestamp = -.infinity
  }

  mutating func admit(timestamp: TimeInterval) -> Ticket? {
    guard active, inFlight == nil, timestamp.isFinite, timestamp > lastTimestamp,
          lastTimestamp == -.infinity || timestamp - lastTimestamp > Self.minimumFrameInterval else { return nil }
    nextFrame &+= 1
    let ticket = Ticket(generation: generation, frame: nextFrame, timestamp: timestamp)
    lastTimestamp = timestamp
    inFlight = ticket
    return ticket
  }

  func owns(_ ticket: Ticket) -> Bool {
    active && ticket.generation == generation && inFlight == ticket
  }

  @discardableResult
  mutating func finish(_ ticket: Ticket, analysisDuration: TimeInterval) -> Bool {
    guard owns(ticket) else { return false }
    inFlight = nil
    lastAnalysisDuration = analysisDuration.isFinite ? max(0, analysisDuration) : nil
    return true
  }
}

struct GarmentCaptureConsensus {
  private(set) var count = 0
  private var candidates: [GarmentScanDimensions] = []

  mutating func add(_ dimensions: GarmentScanDimensions) -> GarmentScanDimensions? {
    if !candidates.allSatisfy({ $0.agrees(with: dimensions) }) { reset() }
    candidates.append(dimensions)
    count = candidates.count
    return GarmentScanDimensions.consensus(candidates)
  }

  mutating func reset() {
    candidates.removeAll()
    count = 0
  }
}

@MainActor
final class GarmentCaptureController: UIViewController, ARSessionDelegate {
  var onResult: ((GarmentCaptureResult) -> Void)?
  var onGuidance: ((String) -> Void)?
  private var preview: ARSCNView?
  private let analyzer = GarmentDepthAnalyzer()
  private var analysis: Task<Void, Never>?
  private var consensus = GarmentCaptureConsensus()
  private var scheduler = GarmentCaptureScheduler()
  private var active = false
  private var orientationInvalid = false
  private var needsRestart = false
  private var cameraRequest: UInt64 = 0

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
    startCamera()
  }

  private func startCamera() {
    cameraRequest &+= 1
    let request = cameraRequest
    Task { [weak self] in
      guard let self, active, request == cameraRequest else { return }
      let allowed: Bool
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized: allowed = true
      case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
      default: allowed = false
      }
      guard active, request == cameraRequest else { return }
      guard allowed else { onGuidance?("Camera access is off. Enable it in Settings, then reopen the scanner."); return }
      guard Self.supported else { onGuidance?("Automatic measurement needs a LiDAR iPhone. You can still add garment photos to your closet."); return }
      if preview == nil {
        let scene = ARSCNView(frame: view.bounds)
        scene.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scene.isUserInteractionEnabled = false
        scene.session.delegateQueue = .main
        scene.session.delegate = self
        view.addSubview(scene)
        preview = scene
      }
      consensus.reset()
      scheduler.start()
      onGuidance?("Searching: center the whole shirt in view, collar at the top, camera directly overhead.")
      let config = ARWorldTrackingConfiguration()
      config.frameSemantics = [.sceneDepth]
      preview?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
  }


  override func viewWillDisappear(_ animated: Bool) { stop(); super.viewWillDisappear(animated) }

  func stop() {
    active = false
    cameraRequest &+= 1
    scheduler.stop()
    analysis?.cancel(); analysis = nil
    preview?.session.delegate = nil
    preview?.session.pause()
    preview?.removeFromSuperview(); preview = nil
    consensus.reset()
  }

  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    MainActor.assumeIsolated {
      guard active, !needsRestart, session === preview?.session else { return }
      guard view.window?.windowScene?.effectiveGeometry.interfaceOrientation == .portrait else {
        if !orientationInvalid {
          consensus.reset()
          scheduler.stop()
          analysis?.cancel(); analysis = nil
          orientationInvalid = true
        }
        onGuidance?("Searching: turn the iPhone upright in portrait, collar toward the top.")
        return
      }
      if orientationInvalid {
        orientationInvalid = false
        consensus.reset()
        scheduler.start()
        onGuidance?("Searching: portrait restored. Center the whole shirt with the collar at the top.")
      }
      guard let ticket = scheduler.admit(timestamp: frame.timestamp) else { return }
      onGuidance?("Recognizing: checking the shirt outline, collar, sleeves, and landmarks.")
      let started = ProcessInfo.processInfo.systemUptime
      analysis = Task { [weak self] in
        guard let self else { return }
        defer {
          let completed = scheduler.finish(ticket, analysisDuration: ProcessInfo.processInfo.systemUptime - started)
          if completed { analysis = nil }
        }
        do {
          let result = try await analyzer.analyze(frame, onStage: { stage in
            Task { @MainActor [weak self] in
              guard let self, scheduler.owns(ticket), active, !needsRestart else { return }
              switch stage {
              case .recognizing: onGuidance?("Recognizing: finding the shirt outline and checking for a single garment.")
              case .landmarks: onGuidance?("Recognizing: checking collar, shoulders, sleeves, and hem landmarks.")
              case .metricDepth: onGuidance?("Checking: verifying tracking, high-confidence LiDAR depth, and camera angle.")
              case .projecting: onGuidance?("Checking: projecting visible edges onto the metric surface.")
              }
            }
          })
          guard scheduler.owns(ticket), active, !needsRestart, !Task.isCancelled else { return }
          if let timings = result.timings {
            onGuidance?("Checking complete. Stabilizing: foreground \(String(format: "%.2f", timings.foregroundSeconds))s, outline \(String(format: "%.2f", timings.silhouetteSeconds))s, landmarks \(String(format: "%.2f", timings.landmarkSeconds))s (\(String(format: "%.1f", timings.landmarkPredictionMS))ms model prediction), depth \(String(format: "%.2f", timings.depthSeconds))s, projection \(String(format: "%.2f", timings.projectionSeconds))s; total \(String(format: "%.2f", timings.totalSeconds))s.")
          }
          if let dimensions = consensus.add(result.dimensions) {
            var accepted = result
            accepted.dimensions = dimensions
            let completion = onResult
            analysis = nil
            stop()
            completion?(accepted)
          } else {
            onGuidance?("Stabilizing: \(consensus.count) of 3 distinct frames agree. Hold still.")
          }
        } catch {
          guard scheduler.owns(ticket), active, !needsRestart, !Task.isCancelled else { return }
          consensus.reset()
          onGuidance?(error.localizedDescription)
        }
      }
    }
  }

  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    MainActor.assumeIsolated {
      guard session === preview?.session else { return }
      needsRestart = true
      scheduler.stop()
      analysis?.cancel(); analysis = nil
      consensus.reset()
      onGuidance?(GarmentCaptureError.interrupted.localizedDescription + " Tap Restart scan to try again.")
    }
  }
  nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
    MainActor.assumeIsolated {
      guard session === preview?.session else { return }
      needsRestart = true
      scheduler.stop()
      analysis?.cancel(); analysis = nil
      consensus.reset()
      onGuidance?("Camera tracking stopped. Tap Restart scan, or close and reopen the scanner.")
    }
  }
}
