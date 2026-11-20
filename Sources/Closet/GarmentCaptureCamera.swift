@preconcurrency import ARKit
import AVFoundation
import SceneKit
import simd
import SwiftUI

struct GarmentCaptureCamera: UIViewControllerRepresentable {
  var onResult: (GarmentCaptureResult) -> Void
  var onGuidance: (String) -> Void
  var onPosition: (ScanPositionFeedback) -> Void
  var onProgress: (Int) -> Void

  func makeUIViewController(context: Context) -> GarmentCaptureController {
    let controller = GarmentCaptureController()
    controller.onResult = onResult
    controller.onGuidance = onGuidance
    controller.onPosition = onPosition
    controller.onProgress = onProgress
    return controller
  }
  func updateUIViewController(_ controller: GarmentCaptureController, context: Context) {
    controller.onResult = onResult; controller.onGuidance = onGuidance
    controller.onPosition = onPosition; controller.onProgress = onProgress
  }
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
  private var candidates: [(dimensions: GarmentScanDimensions, time: TimeInterval)] = []

  mutating func add(_ dimensions: GarmentScanDimensions, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> GarmentScanDimensions? {
    miss(at: time)
    guard dimensions.isValid, time.isFinite else { return nil }
    candidates.append((dimensions, time))
    candidates = Array(candidates.suffix(5))
    count = 1
    for a in candidates.indices.dropLast() {
      if candidates[a].dimensions.agrees(with: dimensions) { count = 2 }
      for b in candidates.indices where b > a && b < candidates.count - 1 {
        if let accepted = GarmentScanDimensions.consensus([candidates[a].dimensions, candidates[b].dimensions, dimensions]) {
          count = 3; return accepted
        }
      }
    }
    return nil
  }

  mutating func add(_ candidate: GarmentCaptureCandidate, at time: TimeInterval = ProcessInfo.processInfo.systemUptime)
    -> (candidate: GarmentCaptureCandidate, dimensions: GarmentScanDimensions)? {
    guard let dimensions = add(candidate.dimensions, at: time) else { return nil }
    return (candidate, dimensions)
  }

  mutating func miss(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    guard time.isFinite else { reset(); return }
    candidates.removeAll { time < $0.time || time - $0.time > 12 }
    count = min(count, candidates.count)
  }

  mutating func reset() {
    candidates.removeAll()
    count = 0
  }
}

enum GarmentCaptureGuidanceGeometry {
  static func viewportBounds(from points: [CGPoint], size: CGSize) -> CGRect? {
    guard points.count == 4, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
          points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), let first = points.first else { return nil }
    var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
    for point in points.dropFirst() {
      minX = min(minX, point.x); minY = min(minY, point.y)
      maxX = max(maxX, point.x); maxY = max(maxY, point.y)
    }
    return CGRect(x: minX / size.width, y: minY / size.height,
                  width: (maxX - minX) / size.width, height: (maxY - minY) / size.height)
  }


  static func nativeCameraUV(fromViewportPoint point: CGPoint, displayTransform: CGAffineTransform) -> CGPoint? {
    let determinant = displayTransform.a * displayTransform.d - displayTransform.b * displayTransform.c
    guard point.x.isFinite, point.y.isFinite, determinant.isFinite, abs(determinant) > 0.000001 else { return nil }
    let uv = point.applying(displayTransform.inverted())
    guard uv.x.isFinite, uv.y.isFinite, (0...1).contains(uv.x), (0...1).contains(uv.y) else { return nil }
    return uv
  }

  static func overheadTilt(transform: simd_float4x4) -> CGPoint {
    let right = SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z)
    let up = SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z)
    let forward = -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
    guard [right.x, right.y, right.z, up.x, up.y, up.z, forward.x, forward.y, forward.z].allSatisfy(\.isFinite) else {
      return CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    }
    let down = SIMD3<Float>(0, -1, 0)
    let vertical = simd_dot(down, forward)
    let horizontal = -up
    return CGPoint(x: CGFloat(atan2(simd_dot(down, right), vertical)),
                   y: CGFloat(atan2(simd_dot(down, horizontal), vertical)))
  }
}

@MainActor
final class GarmentCaptureController: UIViewController, ARSessionDelegate {
  var onResult: ((GarmentCaptureResult) -> Void)?
  var onGuidance: ((String) -> Void)?
  var onPosition: ((ScanPositionFeedback) -> Void)?
  var onProgress: ((Int) -> Void)?
  private var preview: ARSCNView?
  private let analyzer = GarmentDepthAnalyzer()
  private var analysis: Task<Void, Never>?
  private var consensus = GarmentCaptureConsensus()
  private var scheduler = GarmentCaptureScheduler()
  private var active = false
  private var orientationInvalid = false
  private var needsRestart = false
  private var cameraRequest: UInt64 = 0
  private var lastGuidanceAt = -Double.infinity
  private var framing: (corners: [SIMD3<Float>], center: SIMD3<Float>)?
  private var targetDistance: Double?
  private var targetLocked = false
  private var alignedSince: TimeInterval?
  private var guidanceTracker = ScanGuidanceTracker()
  private var currentPosition = ScanPositionFeedback()

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
      needsRestart = false
      orientationInvalid = false
      analysis?.cancel(); analysis = nil
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
      resetGuidance(reacquireTarget: true)
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
    trackingAvailable = false
    resetGuidance(reacquireTarget: true)
  }
  private func resetGuidance(reacquireTarget: Bool) {
    framing = nil
    guidanceTracker.reset()
    alignedSince = nil
    if reacquireTarget { targetDistance = nil; targetLocked = false }
    lastGuidanceAt = -Double.infinity
    currentPosition = ScanPositionFeedback()
    onPosition?(currentPosition)
  }

  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    MainActor.assumeIsolated {
      guard active, !needsRestart, session === preview?.session else { return }
      let now = ProcessInfo.processInfo.systemUptime
      guard view.window?.windowScene?.effectiveGeometry.interfaceOrientation == .portrait else {
        if !orientationInvalid {
          consensus.reset()
          scheduler.stop()
          analysis?.cancel(); analysis = nil
          orientationInvalid = true
          trackingAvailable = false
          resetGuidance(reacquireTarget: true)
          onProgress?(0)
        }
        if now - lastGuidanceAt >= 0.1 {
          var orientationWarning = ScanPositionFeedback()
          orientationWarning.direction = .level
          orientationWarning.severity = 1
          orientationWarning.source = "Phone orientation"
          orientationWarning.observedAt = now
          currentPosition = orientationWarning
          onPosition?(orientationWarning)
          lastGuidanceAt = now
        }
        onGuidance?("Turn the iPhone upright in portrait, with the collar toward the top.")
        return
      }
      if orientationInvalid {
        orientationInvalid = false
        consensus.reset()
        resetGuidance(reacquireTarget: true)
        scheduler.start()
        onGuidance?("Searching: portrait restored. Center the whole shirt with the collar at the top.")
      }
      guard case .normal = frame.camera.trackingState else {
        if trackingAvailable {
          trackingAvailable = false
          resetGuidance(reacquireTarget: true)
        }
        consensus.miss(at: now); onProgress?(consensus.count)
        onGuidance?("Move slowly while camera tracking settles.")
        return
      }
      trackingAvailable = true
      if now - lastGuidanceAt >= 0.1 { updateGuidance(frame: frame, now: now) }
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
          let candidate = try await analyzer.analyze(frame, onStage: { stage in
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
          let observedAt = ProcessInfo.processInfo.systemUptime
          guard let liveFrame = preview?.session.currentFrame else { return }
          updateGuidance(frame: liveFrame, now: observedAt, candidate: candidate)
          guard targetLocked, currentPosition.direction == .hold else {
            onProgress?(consensus.count)
            onGuidance?("Center the whole shirt, hold the phone overhead, and follow the distance guide.")
            return
          }
          if let accepted = consensus.add(candidate, at: observedAt) {
            onProgress?(consensus.count)
            let result = try await analyzer.finalize(accepted.candidate, dimensions: accepted.dimensions)
            guard scheduler.owns(ticket), active, !needsRestart, !Task.isCancelled else { return }
            let completion = onResult
            analysis = nil
            stop()
            completion?(result)
          } else {
            onProgress?(consensus.count)
            onGuidance?("Stabilizing: \(consensus.count) of 3 distinct views agree. Hold steady.")
          }
        } catch {
          guard scheduler.owns(ticket), active, !needsRestart, !Task.isCancelled else { return }
          consensus.miss(at: ProcessInfo.processInfo.systemUptime)
          onProgress?(consensus.count)
          onGuidance?(error.localizedDescription)
        }
      }
    }
  }

  private var trackingAvailable = false

  private func updateGuidance(frame: ARFrame, now: TimeInterval, candidate: GarmentCaptureCandidate? = nil) {
    lastGuidanceAt = now
    let tilt = GarmentCaptureGuidanceGeometry.overheadTilt(transform: frame.camera.transform)
    if let candidate {
      framing = (candidate.worldCorners, candidate.worldCenter)
    }
    // The shirt stays flat; reproject its world bounds using each live camera frame.
    guard let framing else {
      self.framing = nil
      alignedSince = nil
      currentPosition = guidanceTracker.update(
        ScanGuidanceSample(meters: nil, targetMeters: targetDistance, bounds: nil,
                           tilt: tilt, observedAt: now), now: now)
      onPosition?(currentPosition)
      return
    }
    let viewportSize = view.bounds.size
    let camera = frame.camera
    let viewMatrix = camera.viewMatrix(for: .portrait)
    var projected: [CGPoint] = []
    for corner in framing.corners {
      let cameraPoint = viewMatrix * SIMD4(corner.x, corner.y, corner.z, 1)
      guard cameraPoint.z.isFinite, cameraPoint.z < -0.05 else {
        self.framing = nil
        alignedSince = nil
        currentPosition = guidanceTracker.update(
          ScanGuidanceSample(meters: nil, targetMeters: targetDistance, bounds: nil,
                             tilt: tilt, observedAt: now), now: now)
        onPosition?(currentPosition)
        return
      }
      projected.append(camera.projectPoint(corner, orientation: .portrait, viewportSize: viewportSize))
    }
    guard let bounds = GarmentCaptureGuidanceGeometry.viewportBounds(from: projected, size: viewportSize) else {
      self.framing = nil
      alignedSince = nil
      currentPosition = guidanceTracker.update(
        ScanGuidanceSample(meters: nil, targetMeters: targetDistance, bounds: nil,
                           tilt: tilt, observedAt: now), now: now)
      onPosition?(currentPosition)
      return
    }
    let center = camera.projectPoint(framing.center, orientation: .portrait, viewportSize: viewportSize)
    let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
    let nativeCenter = GarmentCaptureGuidanceGeometry.nativeCameraUV(
      fromViewportPoint: CGPoint(x: center.x / viewportSize.width, y: center.y / viewportSize.height),
      displayTransform: displayTransform)
    let depth = frame.sceneDepth
    let meters = nativeCenter.flatMap {
      CaptureDepthSampler.meters(depth?.depthMap, confidence: depth?.confidenceMap, center: $0)
    }
    if !targetLocked, let meters {
      targetDistance = min(2.5, max(0.35, meters * max(bounds.width / 0.82, bounds.height / 0.72)))
    }
    let sample = ScanGuidanceSample(meters: meters, targetMeters: targetDistance, bounds: bounds,
                                    tilt: tilt, observedAt: now)
    currentPosition = guidanceTracker.update(sample, now: now)
    onPosition?(currentPosition)
    guard !targetLocked else { return }
    if currentPosition.direction == .hold {
      alignedSince = alignedSince ?? now
      if now - (alignedSince ?? now) >= 0.6 { targetDistance = meters; targetLocked = true }
    } else {
      alignedSince = nil
    }
  }

  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    MainActor.assumeIsolated {
      guard session === preview?.session else { return }
      needsRestart = true
      trackingAvailable = false
      scheduler.stop()
      analysis?.cancel(); analysis = nil
      consensus.reset()
      resetGuidance(reacquireTarget: true)
      onProgress?(0)
      onGuidance?(GarmentCaptureError.interrupted.localizedDescription + " Tap Restart scan to try again.")
    }
  }
  nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
    MainActor.assumeIsolated {
      needsRestart = true
      trackingAvailable = false
      scheduler.stop()
      analysis?.cancel(); analysis = nil
      consensus.reset()
      resetGuidance(reacquireTarget: true)
      onProgress?(0)
      onGuidance?("Camera tracking stopped. Tap Restart scan, or close and reopen the scanner.")
    }
  }
}
