import ARKit
import AVFoundation
import Foundation
import SceneKit
import SwiftUI
import UIKit
import simd

struct BodyCaptureUpdate {
  var position: ScanPositionFeedback
  var calibrationProgress: Double
  var calibrated: Bool
  var observedAt: TimeInterval?
  var completedViews: Set<BodyCaptureView>
  var missingAngles: [Double]
  var direction: Int
  var captureComplete: Bool
  var instruction: String
  var guide: BodyCaptureGuideState? = nil
}

struct BodyCaptureCamera: UIViewControllerRepresentable {
  let directory: URL
  var seed: BodyCaptureArchive? = nil
  var missingAngles: [Double] = []
  let onReady: (BodyCaptureController) -> Void
  let onUpdate: (BodyCaptureUpdate) -> Void
  let onFinished: (BodyCaptureArchive) -> Void
  let onFailure: (Error) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeUIViewController(context: Context) -> BodyCaptureHostViewController {
    BodyCaptureHostViewController(directory: directory, seed: seed, missingAngles: missingAngles,
                                  onReady: onReady, onUpdate: onUpdate,
                                  onFinished: onFinished, onFailure: onFailure)
  }

  func updateUIViewController(_ controller: BodyCaptureHostViewController, context: Context) {
    controller.setReduceMotion(reduceMotion)
  }

  static func dismantleUIViewController(_ controller: BodyCaptureHostViewController, coordinator: ()) {
    controller.controller?.stop()
  }
}

@MainActor
protocol BodyCaptureControlling: AnyObject {
  func startScanning() async -> Bool
  func finishCapture()
  func setPaused(_ paused: Bool)
  func stop()
}

@MainActor
final class BodyCaptureController: BodyCaptureControlling {
  nonisolated static let supported = ARWorldTrackingConfiguration.isSupported &&
    ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
  nonisolated static let maximumPhotos = 120

  private weak var runtime: BodyCaptureRuntime?

  fileprivate init(runtime: BodyCaptureRuntime) { self.runtime = runtime }

  func startScanning() async -> Bool {
    guard let runtime else { return false }
    return await runtime.startScanning()
  }
  func finishCapture() { runtime?.finishCapture() }
  func setPaused(_ paused: Bool) { runtime?.setPaused(paused) }
  func stop() { runtime?.stop() }
}

@MainActor
final class BodyCaptureHostViewController: UIViewController {
  private let readyHandler: (BodyCaptureController) -> Void
  private let updateHandler: (BodyCaptureUpdate) -> Void
  private let finishedHandler: (BodyCaptureArchive) -> Void
  private let failureHandler: (Error) -> Void
  private var runtime: BodyCaptureRuntime?
  private(set) var controller: BodyCaptureController?
  private var spatialGuide = BodyCaptureSpatialGuide()
  private var guideExpiry: Task<Void, Never>?
  private var latestGuide: BodyCaptureGuideState?
  private var reduceMotion = false

  init(directory: URL, seed: BodyCaptureArchive?, missingAngles: [Double],
       onReady: @escaping (BodyCaptureController) -> Void,
       onUpdate: @escaping (BodyCaptureUpdate) -> Void,
       onFinished: @escaping (BodyCaptureArchive) -> Void,
       onFailure: @escaping (Error) -> Void) {
    readyHandler = onReady
    updateHandler = onUpdate
    finishedHandler = onFinished
    failureHandler = onFailure
    super.init(nibName: nil, bundle: nil)
    let runtime = BodyCaptureRuntime(directory: directory, seed: seed, missingAngles: missingAngles,
                                     onReady: { [weak self] in self?.notifyReady() },
                                     onUpdate: { [weak self] in self?.receive($0) },
                                     onFinished: { [weak self] in self?.finishedHandler($0) },
                                     onFailure: { [weak self] in self?.failureHandler($0) })
    self.runtime = runtime
    controller = BodyCaptureController(runtime: runtime)
  }

  required init?(coder: NSCoder) { return nil }

  override func loadView() {
    let cameraView = ARSCNView(frame: .zero)
    cameraView.scene = SCNScene()
    cameraView.automaticallyUpdatesLighting = false
    cameraView.session = runtime?.session ?? ARSession()
    cameraView.scene.rootNode.addChildNode(spatialGuide.root)
    cameraView.accessibilityElementsHidden = true
    view = cameraView
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateViewport()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    updateViewport()
    runtime?.startSession()
  }

  private func updateViewport() {
    let portrait = view.window?.windowScene?.effectiveGeometry.interfaceOrientation == .portrait
    runtime?.setViewport(size: view.bounds.size, portrait: portrait)
  }

  private func notifyReady() {
    guard let controller else { return }
    readyHandler(controller)
  }

  func setReduceMotion(_ value: Bool) {
    guard reduceMotion != value else { return }
    reduceMotion = value
    spatialGuide.update(latestGuide, now: ProcessInfo.processInfo.systemUptime, reduceMotion: value)
  }

  private func receive(_ update: BodyCaptureUpdate) {
    latestGuide = update.guide
    guideExpiry?.cancel()
    let now = ProcessInfo.processInfo.systemUptime
    spatialGuide.update(update.guide, now: now, reduceMotion: reduceMotion)
    if let guide = update.guide, guide.isFresh(now: now) {
      guideExpiry = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(max(0, (guide.observedAt + 0.6).nextUp - now))) }
        catch { return }
        guard !Task.isCancelled else { return }
        self?.spatialGuide.update(nil, now: ProcessInfo.processInfo.systemUptime, reduceMotion: true)
      }
    }
    updateHandler(update)
  }

  deinit { guideExpiry?.cancel() }
}

enum BodyCaptureCameraError: LocalizedError, Equatable {
  case permission
  case unsupported
  case interrupted
  case insufficientViews

  var errorDescription: String? {
    switch self {
    case .permission: "Camera access is not authorized."
    case .unsupported: "This device does not support body capture with LiDAR."
    case .interrupted: "Camera tracking was interrupted. Set iPhone securely and frame yourself again."
    case .insufficientViews: "There aren’t enough clear views. Retake with a slower turn and steady arms."
    }
  }
}

// Capture state is serial-queue confined; viewport and callback gates use controlLock.
private final class BodyCaptureRuntime: NSObject, ARSessionDelegate, @unchecked Sendable {
  private struct Viewport: Equatable {
    var size = CGSize.zero
    var portrait = false
  }

  private struct CameraSample {
    let time: TimeInterval
    let position: SIMD3<Float>
    let rotation: simd_quatf

    init(time: TimeInterval, transform: simd_float4x4) {
      self.time = time
      position = transform.columns.3.xyz
      rotation = simd_quatf(transform)
    }

    func angle(from other: CameraSample) -> Double {
      let dot = Double(abs(simd_dot(rotation.vector, other.rotation.vector)))
      return 2 * acos(min(1, dot))
    }
  }

  private struct Rates {
    let speed: Double
    let angularSpeed: Double
    var stationary: Bool { speed <= 0.12 && angularSpeed <= 0.22 }
  }

  let session = ARSession()
  private let directory: URL
  private let queue = DispatchQueue(label: "app.onyou.body-capture", qos: .userInitiated)
  private let onReady: @MainActor () -> Void
  private let onUpdate: @MainActor (BodyCaptureUpdate) -> Void
  private let onFinished: @MainActor (BodyCaptureArchive) -> Void
  private let onFailure: @MainActor (Error) -> Void
  private let controlLock = NSLock()
  private var viewport = Viewport()
  private var callbacksEnabled = true
  private var promptVisible = false
  private var observedViewport = Viewport()
  private var sampler: DispatchSourceTimer?
  private var configuration: ARWorldTrackingConfiguration?
  private var readySent = false
  private var interrupted = false
  private var stopped = false
  private var finished = false
  private var captureComplete = false
  private var previousCamera: CameraSample?
  private var lastFrameTimestamp = -Double.infinity
  private var calibration = BodyCaptureCalibration()
  private var baseline: BodyCaptureBaseline?
  private var candidateGuidePlacement: BodyCaptureGuideState.Placement?
  private var guidePlacement: BodyCaptureGuideState.Placement?
  private var cameraReference: CameraSample?
  private var driftBegan: TimeInterval?
  private var recoveryBegan: TimeInterval?
  private var driftBlocked = false
  private var guidance = ScanGuidanceTracker()
  private var turn: BodyCaptureTurn
  private var coverage: BodyCaptureCoverage
  private var samples: [BodyCaptureStoredSample]
  private var nextSampleID: Int
  private let analyzer = BodyCaptureFrameAnalyzer()
  private let writer: BodyCapturePhotoWriter

  init(directory: URL, seed: BodyCaptureArchive?, missingAngles: [Double],
       onReady: @escaping @MainActor () -> Void,
       onUpdate: @escaping @MainActor (BodyCaptureUpdate) -> Void,
       onFinished: @escaping @MainActor (BodyCaptureArchive) -> Void,
       onFailure: @escaping @MainActor (Error) -> Void) {
    self.directory = directory
    self.onReady = onReady
    self.onUpdate = onUpdate
    self.onFinished = onFinished
    self.onFailure = onFailure
    turn = BodyCaptureTurn(direction: seed?.direction, recoveringAngles: missingAngles)
    coverage = seed?.coverage ?? BodyCaptureCoverage()
    samples = seed?.samples ?? []
    nextSampleID = seed?.nextSampleID ?? 0
    writer = BodyCapturePhotoWriter(directory: directory)
    super.init()
    session.delegateQueue = queue
    session.delegate = self
  }

  func setViewport(size: CGSize, portrait: Bool) {
    controlLock.withLock { viewport = Viewport(size: size, portrait: portrait) }
  }

  private var currentViewport: Viewport { controlLock.withLock { viewport } }
  private var canObserve: Bool { controlLock.withLock { callbacksEnabled && !promptVisible } }

  func startSession() {
    queue.async { [weak self] in
      guard let self, !stopped, !finished, configuration == nil else { return }
      guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
        fail(BodyCaptureCameraError.permission)
        return
      }
      guard BodyCaptureController.supported else { fail(BodyCaptureCameraError.unsupported); return }
      var isDirectory: ObjCBool = false
      guard directory.isFileURL,
            FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue else { fail(BodyCaptureArchiveError.missingDirectory); return }
      if nextSampleID > 0 {
        do {
          // A paused recovery may have written samples beyond the last sealed archive.
          for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            guard name.hasPrefix("body-"), let dot = name.firstIndex(of: "."),
                  let id = Int(name[name.index(name.startIndex, offsetBy: 5)..<dot]),
                  id >= 0, id < Int.max else { continue }
            nextSampleID = max(nextSampleID, id + 1)
          }
        } catch {
          fail(error)
          return
        }
      }
      let configuration = ARWorldTrackingConfiguration()
      configuration.frameSemantics = .sceneDepth
      if let format = ARWorldTrackingConfiguration.recommendedVideoFormatFor4KResolution {
        configuration.videoFormat = format
      }
      self.configuration = configuration
      session.run(configuration, options: [])
      // Sample currentFrame, not the delegate's backlog of retained camera buffers.
      let sampler = DispatchSource.makeTimerSource(queue: queue)
      sampler.setEventHandler { [weak self] in self?.sample() }
      sampler.schedule(deadline: .now())
      self.sampler = sampler
      sampler.activate()
    }
  }

  func startScanning() async -> Bool {
    await withCheckedContinuation { continuation in
      queue.async {
        let view = self.currentViewport
        guard !self.stopped, !self.finished, !self.interrupted, self.canObserve, self.baseline == nil,
              view.portrait, view == self.observedViewport,
              let frame = self.session.currentFrame, case .normal = frame.camera.trackingState,
              let reference = self.calibration.lockBaseline(now: ProcessInfo.processInfo.systemUptime) else {
          continuation.resume(returning: false)
          return
        }
        let cameraReference = CameraSample(time: frame.timestamp, transform: reference.cameraTransform)
        let current = CameraSample(time: frame.timestamp, transform: frame.camera.transform)
        guard simd_distance(current.position, cameraReference.position) <= 0.05,
              current.angle(from: cameraReference) <= 5 * .pi / 180 else {
          self.calibration.reset()
          continuation.resume(returning: false)
          return
        }
        self.baseline = reference
        self.guidePlacement = self.candidateGuidePlacement
        self.cameraReference = cameraReference
        self.guidance.reset()
        continuation.resume(returning: true)
      }
    }
  }

  func setPaused(_ visible: Bool) {
    controlLock.withLock { promptVisible = visible }
    queue.async { [weak self] in
      guard let self, !stopped, !finished else { return }
      if baseline == nil { calibration.reset() }
      previousCamera = nil
      turn.resetObservation()
      guidance.reset()
      if visible { publish(instruction: "Scan paused.") }
    }
  }

  func finishCapture() {
    queue.async { [weak self] in
      guard let self, captureComplete, !stopped, !finished else { return }
      finished = true
      stopSession()
      let archive = BodyCaptureArchive(samples: samples, coverage: coverage,
                                       direction: turn.direction ?? 1, nextSampleID: nextSampleID)
      dispatchCallback { [onFinished] in onFinished(archive) }
    }
  }

  func stop() {
    guard controlLock.withLock({
      guard callbacksEnabled else { return false }
      callbacksEnabled = false
      return true
    }) else { return }
    queue.sync {
      stopped = true
      stopSession()
    }
  }

  func session(_ session: ARSession, didFailWithError error: Error) { fail(error) }

  func sessionWasInterrupted(_ session: ARSession) {
    guard !stopped, !finished else { return }
    if baseline != nil { fail(BodyCaptureCameraError.interrupted); return }
    interrupted = true
    calibration.reset()
    previousCamera = nil
    guidance.reset()
    publish(instruction: "Camera tracking paused.")
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    guard !stopped, !finished, interrupted, let configuration else { return }
    interrupted = false
    session.run(configuration, options: [.resetTracking])
  }

  private func sample() {
    guard !stopped, !finished, !captureComplete else { return }
    let start = DispatchTime.now()
    defer { sampler?.schedule(deadline: max(start + .milliseconds(200), .now())) }
    guard canObserve, !interrupted, let frame = session.currentFrame else { return }
    autoreleasepool {
      do { try process(frame, now: ProcessInfo.processInfo.systemUptime) }
      catch { fail(error) }
    }
  }

  private func process(_ frame: ARFrame, now: TimeInterval) throws {
    let view = currentViewport
    guard view.size.width > 1, view.size.height > 1 else { return }
    if !readySent {
      readySent = true
      dispatchCallback { [onReady] in onReady() }
    }
    if view != observedViewport {
      observedViewport = view
      if baseline == nil { calibration.reset() }
      if baseline != nil { turn.resetObservation() }
      guidance.reset()
    }
    guard view.portrait else {
      unavailable("Hold iPhone upright.", at: now,
                  position: ScanPositionFeedback(direction: .level, severity: 1, source: "Phone orientation", observedAt: now))
      return
    }
    guard case .normal = frame.camera.trackingState else {
      previousCamera = nil
      unavailable("Hold still while tracking returns.", at: now)
      return
    }
    guard (0...0.6).contains(now - frame.timestamp) else {
      previousCamera = nil
      unavailable("Hold still while tracking returns.", at: now)
      return
    }
    guard frame.timestamp > lastFrameTimestamp else { return }
    lastFrameTimestamp = frame.timestamp
    let camera = CameraSample(time: frame.timestamp, transform: frame.camera.transform)
    let rates = rates(for: camera)
    if let warning = phonePosition(camera, now: now) {
      unavailable("Keep iPhone in the same spot.", at: now, position: warning)
      return
    }
    let assessment = try analyzer.analyze(frame, viewport: view.size, now: now)
    let currentTime = ProcessInfo.processInfo.systemUptime
    guard canObserve, currentViewport == view else { return }
    guard currentTime - now <= 0.6 else {
      unavailable("Hold there.", at: currentTime)
      return
    }
    switch assessment.issue {
    case .multiplePeople: unavailable("Keep only one person in view.", at: now); return
    case .missingPerson: unavailable("Step into view with your head and feet visible.", at: now); return
    default: break
    }

    let roll = cameraRoll(frame: frame, viewport: view.size)
    let bounds = assessment.bounds
    let suggestedDistance = baseline?.radius ?? bounds.flatMap { bounds in
      assessment.meters.map { min(3, max(0.35, $0 * max(Double(bounds.width) / 0.78, Double(bounds.height) / 0.82))) }
    }
    var position = guidance.update(
      ScanGuidanceSample(meters: assessment.meters, targetMeters: suggestedDistance,
                         bounds: bounds, roll: roll, observedAt: now), now: currentTime)
    let framingOK = !assessment.clipped && (bounds.map(Self.fits) ?? false)
    let minimumHeight = max(0.45, (baseline?.previewHeight ?? 0) * 0.82)
    let sizeOK = bounds.map { $0.height >= minimumHeight } ?? false
    if position.direction == .hold, let bounds {
      let x = bounds.midX - 0.5, y = bounds.midY - 0.5
      if baseline == nil && abs(roll) > 8 * .pi / 180 {
        position.direction = .level
        position.severity = 0.2
      } else if baseline == nil && max(abs(x), abs(y)) > 0.10 {
        position.direction = abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
        position.severity = 0.2
      } else if !framingOK {
        position.direction = .farther
        position.severity = 0.3
      } else if !sizeOK {
        position.direction = .closer
        position.severity = 0.2
      }
    }
    let directed = position.intensity > 0 ? positioningInstruction(position.direction) : nil
    let correction: String?
    if !framingOK || !sizeOK {
      correction = directed ?? "Keep your head and feet visible."
    } else if let directed {
      correction = directed
    } else if assessment.meters == nil || assessment.issue == .depth {
      correction = "We need a clearer view. Keep your head and feet visible in even light."
    } else if baseline == nil && !assessment.frontFacing {
      correction = "Face the camera."
    } else if baseline == nil && !assessment.fullBody {
      correction = "Keep your head and feet visible."
    } else if !assessment.armsApart {
      correction = "Hold your arms slightly away."
    } else if assessment.issue == .pose {
      correction = "Hold that position."
    } else {
      correction = nil
    }

    // Vision sees an upright portrait camera. Undo that camera's rotation, not the person's turn.
    let portraitToWorld = frame.camera.viewMatrix(for: .portrait).inverse
    let shoulders = assessment.shoulderAxis.map { (portraitToWorld * SIMD4<Float>($0, 0)).xyz }
    let hips = assessment.hipAxis.map { (portraitToWorld * SIMD4<Float>($0, 0)).xyz }
    let up = assessment.up.map { (portraitToWorld * SIMD4<Float>($0, 0)).xyz }
    if let baseline {
      let yaw = shoulders.flatMap { shoulders in
        hips.flatMap { BodyCaptureTurn.yaw(shoulders: shoulders, hips: $0, referenceAxis: baseline.referenceAxis, up: baseline.up) }
      }
      var feedback = turn.update(yaw: yaw, observedAt: now, now: currentTime,
                                 usable: correction == nil && position.direction == .hold, coverage: coverage)
      var cue = correction ?? feedback.instruction
      if let yaw = turn.admissibleYaw, let mask = assessment.mask, coverage.canRecord(azimuth: yaw) {
        if let rates, let turnRate = turn.yawRate, sharp(frame, width: assessment.sourcePersonWidth,
                                                       turnRate: turnRate, angularSpeed: rates.angularSpeed) {
          if samples.count >= BodyCaptureController.maximumPhotos { throw BodyCaptureCameraError.insufficientViews }
          let sample = try writer.write(frame: frame, sampleID: nextSampleID, azimuth: yaw,
                                        fullBody: assessment.fullBody && assessment.frontFacing &&
                                          BodyCaptureCoverage.distance(yaw, 0) <= .pi / 12, mask: mask)
          guard coverage.record(sampleID: sample.sampleID, imageURL: sample.imageURL,
                                azimuth: sample.azimuth, fullBody: sample.fullBody) else {
            throw AvatarScanError.insufficientCoverage
          }
          nextSampleID += 1
          samples.append(sample)
          turn.recorded(yaw)
          feedback = turn.feedback(coverage: coverage)
          cue = feedback.instruction
        } else {
          cue = "Hold that position."
        }
      }
      captureComplete = feedback.captureComplete
      if !captureComplete && turn.isRecovering && feedback.missingAngles.isEmpty {
        throw BodyCaptureCameraError.insufficientViews
      }
      publish(instruction: captureComplete ? "Checking your scan…" : cue,
              position: captureComplete ? ScanPositionFeedback() : position, at: now, feedback: feedback,
              showGuide: correction == nil && position.direction == .hold)
    } else {
      if correction == nil, let rates, let meters = assessment.meters, let bounds, let uv = assessment.torsoUV,
         let shoulders, let hips, let up, simd_length_squared(up) > 1e-6,
         let axis = BodyCaptureTurn.horizontalAxis(shoulders: shoulders, hips: hips, up: up),
         let target = worldPoint(frame: frame, uv: uv, depth: meters) {
        candidateGuidePlacement = guidePlacement(frame: frame, bounds: bounds, meters: meters,
                                                  up: simd_normalize(up), viewport: view.size)
        calibration.update(BodyCaptureCalibrationObservation(
          observedAt: now, meters: meters, targetWorld: target, cameraTransform: frame.camera.transform,
          referenceAxis: axis, up: simd_normalize(up), roll: roll, bounds: bounds,
          fullBody: assessment.fullBody, frontFacing: assessment.frontFacing, trackingNormal: true,
          stationary: rates.stationary && position.direction == .hold), now: currentTime)
      } else {
        calibration.update(nil, now: currentTime)
        candidateGuidePlacement = nil
      }
      let ready = calibration.ready(now: currentTime)
      publish(instruction: correction ?? (ready ? "Framing ready. Hold your pose." : "Hold still with your arms slightly away."),
              position: position, at: now)
    }
  }

  private func positioningInstruction(_ direction: ScanPositionFeedback.Direction) -> String {
    switch direction {
    case .closer: "Move a little closer to iPhone."
    case .farther: "Move a little farther back."
    case .left, .right: "Center yourself in the camera view."
    case .up, .down:
      baseline == nil ? "Position iPhone so your head and feet fit in view." : "Keep your head and feet visible without moving iPhone."
    case .level:
      baseline == nil ? "Set iPhone upright and level on its support." : "Keep iPhone fixed in its original position."
    case .hold: "Hold that position."
    case .searching: "Step into view with your head and feet visible."
    }
  }

  private static func fits(_ bounds: CGRect) -> Bool {
    bounds.minX >= 0.02 && bounds.minY >= 0.02 && bounds.maxX <= 0.98 && bounds.maxY <= 0.98
  }

  private func rates(for camera: CameraSample) -> Rates? {
    defer { previousCamera = camera }
    guard let previousCamera else { return nil }
    let elapsed = camera.time - previousCamera.time
    guard (0.04...0.6).contains(elapsed) else { return nil }
    let speed = Double(simd_distance(camera.position, previousCamera.position)) / elapsed
    let angular = camera.angle(from: previousCamera) / elapsed
    guard speed.isFinite, angular.isFinite else { return nil }
    return Rates(speed: speed, angularSpeed: angular)
  }

  private func phonePosition(_ camera: CameraSample, now: TimeInterval) -> ScanPositionFeedback? {
    guard let cameraReference else { return nil }
    let displacement = Double(simd_distance(camera.position, cameraReference.position))
    let degrees = camera.angle(from: cameraReference) * 180 / .pi
    if driftBlocked {
      if displacement <= 0.08 && degrees <= 5 {
        let start = recoveryBegan ?? now
        recoveryBegan = start
        if now - start >= 0.4 { driftBlocked = false; recoveryBegan = nil }
      } else { recoveryBegan = nil }
    } else if displacement > 0.12 || degrees > 8 {
      let start = driftBegan ?? now
      driftBegan = start
      if now - start >= 0.25 { driftBlocked = true; driftBegan = nil }
    } else { driftBegan = nil }
    guard driftBlocked || driftBegan != nil else { return nil }
    let severity = min(1, max(0.12, (displacement - 0.08) / 0.30, (degrees - 5) / 25))
    return ScanPositionFeedback(direction: .level, severity: driftBlocked ? severity : 0,
                                source: "Phone position", observedAt: now)
  }

  private func sharp(_ frame: ARFrame, width: Double, turnRate: Double, angularSpeed: Double) -> Bool {
    let exposure = frame.camera.exposureDuration, intrinsics = frame.camera.intrinsics
    let focal = Double(max(intrinsics.columns.0.x, intrinsics.columns.1.y))
    return exposure.isFinite && exposure > 0 && width.isFinite && width > 0 && focal.isFinite && focal > 0
      && abs(turnRate) * exposure * width / 2 <= 2 && angularSpeed * exposure * focal <= 2
  }

  private func worldPoint(frame: ARFrame, uv: CGPoint, depth: Double) -> SIMD3<Float>? {
    let intrinsics = frame.camera.intrinsics, size = frame.camera.imageResolution
    let fx = intrinsics.columns.0.x, fy = intrinsics.columns.1.y, z = Float(depth)
    guard fx > 0, fy > 0 else { return nil }
    let x = (Float(uv.x * size.width) - intrinsics.columns.2.x) * z / fx
    let y = -(Float(uv.y * size.height) - intrinsics.columns.2.y) * z / fy
    let point = (frame.camera.transform * SIMD4<Float>(x, y, -z, 1)).xyz
    return simd_length_squared(point).isFinite ? point : nil
  }

  private func cameraRoll(frame: ARFrame, viewport: CGSize) -> Double {
    let transform = frame.camera.transform
    let origin = transform.columns.3.xyz - transform.columns.2.xyz * 2
    let first = frame.camera.projectPoint(origin, orientation: .portrait, viewportSize: viewport)
    let second = frame.camera.projectPoint(origin + SIMD3<Float>(0, 1, 0), orientation: .portrait, viewportSize: viewport)
    let dx = Double(second.x - first.x), dy = Double(second.y - first.y)
    return hypot(dx, dy) > 0.01 ? atan2(dx, -dy) : .pi / 2
  }

  private func unavailable(_ instruction: String, at now: TimeInterval,
                           position: ScanPositionFeedback = ScanPositionFeedback()) {
    guidance.reset()
    if baseline == nil { calibration.reset() }
    else { _ = turn.update(yaw: nil, observedAt: now, now: now, usable: false, coverage: coverage) }
    publish(instruction: instruction, position: position, at: now)
  }

  private func publish(instruction: String, position: ScanPositionFeedback = ScanPositionFeedback(),
                       at time: TimeInterval? = nil, feedback: BodyCaptureTurnFeedback? = nil,
                       showGuide: Bool = false) {
    let feedback = feedback ?? turn.feedback(coverage: coverage)
    let ready = baseline == nil && calibration.ready(now: ProcessInfo.processInfo.systemUptime)
    let guide = showGuide ? guidePlacement.map {
      BodyCaptureGuideState(placement: $0, capturedBins: BodyCaptureGuideState.capturedBins(in: coverage),
                            yaw: turn.admissibleYaw, neededAngle: feedback.missingAngles.first,
                            observedAt: time ?? ProcessInfo.processInfo.systemUptime)
    } : nil
    let update = BodyCaptureUpdate(position: position, calibrationProgress: calibration.progress,
                                   calibrated: ready,
                                   observedAt: time, completedViews: feedback.completedViews,
                                   missingAngles: feedback.missingAngles, direction: turn.direction ?? 1,
                                   captureComplete: captureComplete, instruction: instruction, guide: guide)
    dispatchCallback { [onUpdate] in onUpdate(update) }
  }

  private func guidePlacement(frame: ARFrame, bounds: CGRect, meters: Double,
                              up: SIMD3<Float>, viewport: CGSize) -> BodyCaptureGuideState.Placement? {
    let display = frame.displayTransform(for: .portrait, viewportSize: viewport)
    let determinant = display.a * display.d - display.b * display.c
    guard determinant.isFinite, abs(determinant) > 1e-6 else { return nil }
    let inverse = display.inverted()
    func world(_ x: CGFloat, _ y: CGFloat) -> SIMD3<Float>? {
      worldPoint(frame: frame, uv: CGPoint(x: x, y: y).applying(inverse), depth: meters)
    }
    guard let center = world(bounds.midX, bounds.midY),
          let top = world(bounds.midX, bounds.minY), let bottom = world(bounds.midX, bounds.maxY),
          let left = world(bounds.minX, bounds.midY), let rightEdge = world(bounds.maxX, bounds.midY) else { return nil }
    let towardCamera = frame.camera.transform.columns.3.xyz - center
    let horizontal = simd_cross(up, towardCamera)
    guard simd_length_squared(horizontal) > 1e-6 else { return nil }
    let right = simd_normalize(horizontal)
    let normal = simd_normalize(simd_cross(right, up))
    let height = abs(simd_dot(top - bottom, up)) * 0.5 + 0.06
    let width = max(abs(simd_dot(rightEdge - left, right)) * 0.5 + 0.07, height * 0.46)
    guard height.isFinite, width.isFinite, height > 0.1, width > 0.1 else { return nil }
    let transform = simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(normal, 0), SIMD4(center, 1)))
    return BodyCaptureGuideState.Placement(transform: transform, halfSize: SIMD2(width, height))
  }

  private func stopSession() {
    sampler?.cancel()
    sampler = nil
    session.delegate = nil
    session.pause()
  }

  private func fail(_ error: Error) {
    guard !stopped, !finished else { return }
    finished = true
    stopSession()
    dispatchCallback { [onFailure] in onFailure(error) }
  }

  private func dispatchCallback(_ callback: @escaping @MainActor () -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.controlLock.withLock({ self.callbacksEnabled }) else { return }
      callback()
    }
  }
}


private extension simd_float4 {
  var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
