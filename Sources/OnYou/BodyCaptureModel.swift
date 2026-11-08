import AVFoundation
import Foundation
import Observation
import OSLog
import RealityKit
import SwiftUI

@MainActor @Observable
final class BodyCaptureModel {
  enum Phase: Equatable {
    case setup, preparing, capturing, reconstructing, review, failed(String)
  }

  private(set) var phase = Phase.setup
  private(set) var capture: ObjectCaptureSession?
  private(set) var progress: Double = 0
  private(set) var completedPasses = 0
  private(set) var calibration: AvatarScanCalibration?
  private(set) var modelURL: URL?
  private(set) var imageCount = 0
  private(set) var trackingInterrupted = false
  private(set) var captureStartedAt: Date?
  private(set) var pendingAction: BodyScanCameraStatus.Action?
  private(set) var selectionHint: String?
  private(set) var estimatedRemainingTime: TimeInterval?
  private(set) var hasBuildProgress = false
  private(set) var saveError: String?
  private static let logger = Logger(subsystem: "app.onyou", category: "BodyCapture")
  private var recordedCurrentPass = false
  var stage = "Aligning images"
  private var work: URL?
  private var reconstruction: PhotogrammetrySession?
  private var task: Task<Void, Never>?
  private var generation = UUID()

  static var isSupported: Bool { ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported }

  var canFinish: Bool {
    guard let capture else { return false }
    return capture.state == .capturing
      && Self.hasCoverage(images: capture.numberOfShotsTaken, passes: completedPasses)
      && !trackingInterrupted
  }

  var cameraStatus: BodyScanCameraStatus {
    guard let capture else { return BodyScanCameraStatus(mode: .initializing) }
    let mode: BodyScanCameraStatus.Mode
    switch capture.state {
    case .ready: mode = .framing
    case .detecting: mode = .selecting
    case .capturing: mode = .capturing
    case .finishing, .completed: mode = .finishing
    default: mode = .initializing
    }
    let feedback = capture.feedback
    let issue: String?
    if mode == .finishing { issue = nil }
    else if capture.isPaused { issue = "Capture is paused. Keep On You in the foreground to continue." }
    else if feedback.contains(.environmentTooDark) || feedback.contains(.environmentLowLight) { issue = "Find brighter, even light so we can see the person clearly." }
    else if feedback.contains(.movingTooFast) { issue = "Slow down. Keep the iPhone steady and the person still." }
    else if feedback.contains(.outOfFieldOfView) { issue = "Step back and bring the whole person into view." }
    else if feedback.contains(.objectTooClose) { issue = "Move back a little. Keep their head and feet visible." }
    else if feedback.contains(.objectTooFar) { issue = "Move a little closer without cutting off their head or feet." }
    else if feedback.contains(.objectNotDetected) && mode != .framing { issue = "Keep the person centered inside the selection box." }
    else if capture.cameraTracking != .normal { issue = "Slowly move the iPhone so it can find the floor and settle its tracking." }
    else { issue = nil }
    return BodyScanCameraStatus(mode: mode, completedPasses: completedPasses,
                               shots: capture.numberOfShotsTaken, passComplete: capture.userCompletedScanPass,
                               trackingNormal: capture.cameraTracking == .normal, issue: issue,
                               selectionHint: selectionHint, pendingAction: pendingAction)
  }

  func performCameraAction() {
    guard let capture, cameraStatus.actionEnabled, let action = cameraStatus.action else { return }
    Self.logger.info("Capture action: \(String(describing: action), privacy: .public)")
    selectionHint = nil
    switch action {
    case .findPerson:
      pendingAction = .findPerson
      if !capture.startDetecting() {
        pendingAction = nil
        selectionHint = "We couldn’t find the floor yet. Include the space around their feet, move the iPhone slowly, then try again."
      }
    case .startCapture:
      pendingAction = .startCapture
      capture.startCapturing()
    case .nextPass: nextPass()
    case .buildAvatar: finish()
    }
  }

  func actionTimedOut(_ action: BodyScanCameraStatus.Action) {
    guard phase == .capturing, pendingAction == action, action != .buildAvatar else { return }
    pendingAction = nil
    selectionHint = "Still getting ready. Hold the iPhone steady with the full person and floor in view, then try again."
  }

  func clearSaveError() { saveError = nil }

  static func hasCoverage(images: Int, passes: Int) -> Bool { images >= 60 && passes >= 2 }

  func start() async {
    guard Self.isSupported else { phase = .failed(AvatarScanError.unsupported.localizedDescription); return }
    cancel()
    phase = .preparing
    let token = generation
    let permission: Bool
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: permission = true
    case .notDetermined: permission = await AVCaptureDevice.requestAccess(for: .video)
    default: permission = false
    }
    guard generation == token else { return }
    guard permission else { phase = .failed(AvatarScanError.unavailableCamera.localizedDescription); return }
    do {
      let root = URL.applicationSupportDirectory.appendingPathComponent("OnYouCaptureWork", isDirectory: true)
      try AvatarScanStore.prepareDirectory(root)
      let capacity = try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber
      guard let capacity, capacity.int64Value >= 2_000_000_000 else { throw AvatarScanError.insufficientSpace }
      // No capture is active here. Remove only this subsystem's abandoned UUID attempts.
      for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where UUID(uuidString: url.lastPathComponent) != nil {
        try FileManager.default.removeItem(at: url)
      }
      let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try AvatarScanStore.prepareDirectory(directory)
      work = directory
      let images = directory.appendingPathComponent("Images", isDirectory: true)
      try AvatarScanStore.prepareDirectory(images)
      let checkpoints = directory.appendingPathComponent("Checkpoints", isDirectory: true)
      try AvatarScanStore.prepareDirectory(checkpoints)
      var configuration = ObjectCaptureSession.Configuration()
      configuration.checkpointDirectory = checkpoints
      configuration.isOverCaptureEnabled = false
      let session = ObjectCaptureSession()
      capture = session
      phase = .capturing
      session.start(imagesDirectory: images, configuration: configuration)
    } catch { fail(error) }
  }

  func stateChanged(_ state: ObjectCaptureSession.CaptureState) {
    guard phase == .capturing else { return }
    Self.logger.info("Capture state: \(String(describing: self.cameraStatus.mode), privacy: .public); photos: \(self.capture?.numberOfShotsTaken ?? 0); passes: \(self.completedPasses)")
    selectionHint = nil
    switch state {
    case .detecting:
      pendingAction = nil
    case .capturing:
      pendingAction = nil
      if captureStartedAt == nil { captureStartedAt = Date() }
    case .finishing:
      pendingAction = nil
    case .completed:
      imageCount = capture?.numberOfShotsTaken ?? 0
      capture = nil
      guard Self.hasCoverage(images: imageCount, passes: completedPasses), !trackingInterrupted else {
        fail(AvatarScanError.insufficientCoverage); return
      }
      reconstruct()
    case .failed(let error): fail(error)
    default: break
    }
  }

  func passCompleted(_ completed: Bool) {
    guard phase == .capturing else { return }
    if !completed {
      if pendingAction == .nextPass { pendingAction = nil }
      return
    }
    guard !recordedCurrentPass else { return }
    recordedCurrentPass = true
    completedPasses += 1
    captureProgressChanged()
  }

  func captureProgressChanged() {
    guard phase == .capturing, let capture, capture.state == .capturing,
          cameraStatus.awaitsNextStep, !capture.isPaused else { return }
    // Stop taking extra photos while the person reads the next-step guidance.
    capture.pause()
    Self.logger.info("Capture paused at checkpoint; photos: \(capture.numberOfShotsTaken); passes: \(self.completedPasses)")
  }

  func nextPass() {
    guard let capture, capture.state == .capturing, capture.userCompletedScanPass else { return }
    pendingAction = .nextPass
    recordedCurrentPass = false
    selectionHint = nil
    capture.beginNewScanPass()
    capture.resume()
  }

  func finish() {
    guard canFinish, pendingAction == nil else { return }
    pendingAction = .buildAvatar
    capture?.finish()
  }

  func suspend() {
    if phase == .capturing || phase == .preparing || phase == .reconstructing {
      trackingInterrupted = true
      fail(CaptureInterrupted())
    }
  }

  func save(to store: AvatarScanStore) -> Bool {
    guard phase == .review, let modelURL, let calibration else { return false }
    do {
      try store.save(model: modelURL, calibration: calibration, imageCount: imageCount, completedPasses: completedPasses)
      cancel()
      return true
    } catch {
      saveError = error.localizedDescription
      return false
    }
  }

  func cancel() {
    generation = UUID()
    task?.cancel()
    task = nil
    capture?.cancel()
    capture = nil
    reconstruction?.cancel()
    reconstruction = nil
    if let work { try? FileManager.default.removeItem(at: work) }
    work = nil
    modelURL = nil
    calibration = nil
    completedPasses = 0
    imageCount = 0
    trackingInterrupted = false
    captureStartedAt = nil
    pendingAction = nil
    selectionHint = nil
    estimatedRemainingTime = nil
    hasBuildProgress = false
    saveError = nil
    recordedCurrentPass = false
    progress = 0
    phase = .setup
  }

  private func fail(_ error: Error) {
    Self.logger.error("Capture failed: \(error.localizedDescription, privacy: .private)")
    cancel()
    phase = .failed(error.localizedDescription)
  }

  private func reconstruct() {
    guard let work else { fail(AvatarScanError.invalidModel); return }
    phase = .reconstructing
    let token = generation
    task = Task { [weak self] in
      guard let self else { return }
      do {
        // Metric scale must come from captured depth, never a guessed height.
        stage = "Checking your capture"
        let images = work.appendingPathComponent("Images")
        let files = try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)
          .filter { ["heic", "heif"].contains($0.pathExtension.lowercased()) }
        var depthSamples = 0
        for file in files {
          try Task.checkCancellation()
          guard generation == token else { return }
          let sample = try await PhotogrammetrySample(contentsOf: file)
          if sample.depthDataMap != nil { depthSamples += 1 }
        }
        guard depthSamples >= max(20, imageCount / 2) else { throw AvatarScanError.missingDepth }
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = work.appendingPathComponent("Checkpoints")
        configuration.isObjectMaskingEnabled = true
        configuration.featureSensitivity = .high
        configuration.sampleOrdering = .sequential
        let session = try PhotogrammetrySession(input: work.appendingPathComponent("Images"), configuration: configuration)
        reconstruction = session
        let destination = work.appendingPathComponent("avatar.usdz")
        try session.process(requests: [.modelFile(url: destination, detail: .reduced)])
        var rejected = Set<Int>()
        var producedFile = false
        for try await output in session.outputs {
          try Task.checkCancellation()
          guard generation == token else { return }
          switch output {
          case .requestProgress(_, let fraction):
            if fraction.isFinite {
              hasBuildProgress = true
              progress = max(progress, min(0.99, max(0, fraction)))
            }
          case .requestProgressInfo(_, let info):
            if let value = info.processingStage { stage = title(value) }
            if let seconds = info.estimatedRemainingTime, seconds.isFinite, seconds > 0 {
              estimatedRemainingTime = seconds
            } else { estimatedRemainingTime = nil }
          case .requestComplete(_, .modelFile(let url)):
            producedFile = url.standardizedFileURL == destination.standardizedFileURL
          case .invalidSample(let id, _), .skippedSample(let id): rejected.insert(id)
          case .stitchingIncomplete: throw AvatarScanError.insufficientCoverage
          case .requestError(_, let error): throw error
          case .processingCancelled: throw CancellationError()
          case .processingComplete:
            guard producedFile, Self.hasCoverage(images: imageCount - rejected.count, passes: completedPasses) else {
              throw AvatarScanError.insufficientCoverage
            }
            stage = "Checking your avatar"
            estimatedRemainingTime = nil
            _ = try AvatarScanStore.digest(destination)
            let result = try ScannedAvatarGeometry.load(url: destination)
            calibration = result.calibration
            modelURL = destination
            reconstruction = nil
            progress = 1
            phase = .review
            // Keep only the reconstruction for review; raw photos and checkpoints are temporary.
            try? FileManager.default.removeItem(at: work.appendingPathComponent("Images"))
            try? FileManager.default.removeItem(at: work.appendingPathComponent("Checkpoints"))
            return
          default: break
          }
        }
        if phase != .review { throw AvatarScanError.invalidModel }
      } catch {
        guard generation == token else { return }
        fail(error)
      }
    }
  }

  private func title(_ stage: PhotogrammetrySession.Output.ProcessingStage) -> String {
    switch stage {
    case .preProcessing: "Preparing your photos"
    case .imageAlignment: "Matching your photos"
    case .pointCloudGeneration: "Shaping your avatar"
    case .meshGeneration: "Refining your shape"
    case .textureMapping: "Adding color and detail"
    case .optimization: "Finishing your avatar"
    @unknown default: "Building avatar"
    }
  }
}

private struct CaptureInterrupted: LocalizedError {
  var errorDescription: String? { "The scan was interrupted. Start again so all views share the same tracking and scale." }
}
