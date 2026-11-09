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
  private(set) var preparedScene: PreparedAvatarScene?
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
  private var diagnosticStage: BodyScanTiming.Stage?
  private var diagnosticStartedAt: ContinuousClock.Instant?


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
    let nativeFeedback = capture.feedback
    var feedback = Set<BodyScanCameraStatus.Feedback>()
    if nativeFeedback.contains(.environmentTooDark) { feedback.insert(.environmentTooDark) }
    if nativeFeedback.contains(.environmentLowLight) { feedback.insert(.environmentLowLight) }
    if nativeFeedback.contains(.movingTooFast) { feedback.insert(.movingTooFast) }
    if nativeFeedback.contains(.outOfFieldOfView) { feedback.insert(.outOfFieldOfView) }
    if nativeFeedback.contains(.objectTooClose) { feedback.insert(.objectTooClose) }
    if nativeFeedback.contains(.objectTooFar) { feedback.insert(.objectTooFar) }
    if nativeFeedback.contains(.objectNotDetected) { feedback.insert(.objectNotDetected) }
    let trackingNormal = capture.cameraTracking == .normal
    let issue = mode == .finishing ? nil : BodyScanCameraStatus.guidance(
      for: feedback, mode: mode, capturePaused: capture.isPaused, trackingNormal: trackingNormal)?.message
    return BodyScanCameraStatus(mode: mode, completedPasses: completedPasses,
                               shots: capture.numberOfShotsTaken, passComplete: capture.userCompletedScanPass,
                               trackingNormal: trackingNormal, issue: issue,
                               selectionHint: selectionHint, pendingAction: pendingAction,
                               maximumShots: capture.maximumNumberOfInputImages)
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
    case .retakeScan: cancel()
    }
  }

  func actionTimedOut(_ action: BodyScanCameraStatus.Action) {
    guard phase == .capturing, pendingAction == action, action != .buildAvatar else { return }
    pendingAction = nil
    selectionHint = "Still getting ready. Hold the iPhone steady with the full person and floor in view, then try again."
  }

  func clearSaveError() { saveError = nil }

  static func hasCoverage(images: Int, passes: Int) -> Bool { AvatarScanInput.hasCoverage(images: images, passes: passes) }

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
      beginDiagnosticStage(.framing)
      session.start(imagesDirectory: images, configuration: configuration)
    } catch { fail(error) }
  }

  func stateChanged(_ state: ObjectCaptureSession.CaptureState) {
    guard phase == .capturing else { return }
    Self.logger.info("Capture state: \(String(describing: self.cameraStatus.mode), privacy: .public); photos: \(self.capture?.numberOfShotsTaken ?? 0); passes: \(self.completedPasses)")
    selectionHint = nil
    switch state {
    case .ready:
      beginDiagnosticStage(.framing)
    case .detecting:
      pendingAction = nil
      beginDiagnosticStage(.selection)
    case .capturing:
      pendingAction = nil
      if captureStartedAt == nil { captureStartedAt = Date() }
      beginDiagnosticStage(completedPasses == 0 ? .bodyPass : .detailPass)
    case .finishing:
      pendingAction = nil
      beginDiagnosticStage(.captureFinalization)
    case .completed:
      endDiagnosticStage()
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

  func captureProgressChanged() {
    guard phase == .capturing, let capture, capture.state == .capturing else { return }
    // Reconcile current SDK values; SwiftUI may deliver the photo and ring observers in either order.
    if capture.userCompletedScanPass && !recordedCurrentPass {
      recordedCurrentPass = true
      completedPasses += 1
      beginDiagnosticStage(.passCheckpoint)
    } else if !capture.userCompletedScanPass && pendingAction == .nextPass {
      recordedCurrentPass = false
      pendingAction = nil
    }
    guard pendingAction != .nextPass, cameraStatus.awaitsNextStep,
          !cameraStatus.exhaustedCaptureCapacity, !capture.isPaused else { return }
    // Stop taking extra photos while the person reads the next-step guidance.
    capture.pause()
    Self.logger.info("Capture paused at checkpoint; photos: \(capture.numberOfShotsTaken); passes: \(self.completedPasses)")
  }

  func nextPass() {
    guard let capture, capture.state == .capturing, capture.userCompletedScanPass else { return }
    pendingAction = .nextPass
    beginDiagnosticStage(completedPasses == 0 ? .bodyPass : .detailPass)
    selectionHint = nil
    capture.beginNewScanPass()
    capture.resume()
    captureProgressChanged()
  }

  func setCapturePromptVisible(_ visible: Bool) {
    guard phase == .capturing, let capture, capture.state == .capturing else { return }
    if visible { capture.pause() }
    else if !cameraStatus.awaitsNextStep { capture.resume() }
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
    endDiagnosticStage()
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
    preparedScene = nil
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
        beginDiagnosticStage(.photoPreflight)
        let images = work.appendingPathComponent("Images")
        let files = try FileManager.default.contentsOfDirectory(at: images, includingPropertiesForKeys: nil)
          .filter { ["heic", "heif"].contains($0.pathExtension.lowercased()) }.map(\.standardizedFileURL)
        try Task.checkCancellation()
        guard generation == token else { return }
        let input = try await AvatarScanInput.preflight(files: files)
        try Task.checkCancellation()
        guard generation == token else { return }
        imageCount = try input.validate(passes: completedPasses)
        beginDiagnosticStage(.reconstruction)
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = work.appendingPathComponent("Checkpoints")
        configuration.isObjectMaskingEnabled = true
        configuration.featureSensitivity = .high
        configuration.sampleOrdering = .sequential
        let session = try PhotogrammetrySession(input: work.appendingPathComponent("Images"), configuration: configuration)
        reconstruction = session
        let destination = work.appendingPathComponent("avatar.usdz")
        let modelRequest = PhotogrammetrySession.Request.modelFile(url: destination, detail: .reduced)
        try session.process(requests: [modelRequest, .poses])
        var rejected = Set<Int>()
        var producedFile = false
        var usedPoses: PhotogrammetrySession.Poses?
        for try await output in session.outputs {
          try Task.checkCancellation()
          guard generation == token else { return }
          switch output {
          case .requestProgress(let request, let fraction) where request == modelRequest:
            if let nextProgress = BodyScanTiming.buildProgress(current: progress, fraction: fraction) {
              hasBuildProgress = true
              progress = nextProgress
            }
          case .requestProgressInfo(let request, let info) where request == modelRequest:
            if let value = info.processingStage { stage = title(value) }
            if let seconds = info.estimatedRemainingTime, seconds.isFinite, seconds > 0 {
              estimatedRemainingTime = seconds
            } else { estimatedRemainingTime = nil }
          case .requestComplete(_, .modelFile(let url)):
            producedFile = url.resolvingSymlinksInPath().standardizedFileURL
              == destination.resolvingSymlinksInPath().standardizedFileURL
          case .requestComplete(_, .poses(let poses)): usedPoses = poses
          case .invalidSample(let id, _), .skippedSample(let id): rejected.insert(id)
          case .stitchingIncomplete: throw AvatarScanError.insufficientCoverage
          case .requestError(_, let error): throw error
          case .processingCancelled: throw CancellationError()
          case .processingComplete:
            guard producedFile, let usedPoses else {
              throw AvatarScanError.insufficientCoverage
            }
            imageCount = try input.validate(usedSampleIDs: Set(usedPoses.posesBySample.keys),
                                            urlsBySample: usedPoses.urlsBySample, rejectedIDs: rejected,
                                            passes: completedPasses)
            endDiagnosticStage()
            stage = "Checking your avatar"
            let prepared = try await PreparedAvatarScene.load(url: destination)
            try Task.checkCancellation()
            guard generation == token else { return }
            if let timings = prepared.loadTimings {
              BodyScanTiming.record(.textureValidation,duration: timings.validation)
              BodyScanTiming.record(.avatarLoading,duration: timings.scene)
            }
            calibration = prepared.calibration
            preparedScene = prepared
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

  private func beginDiagnosticStage(_ next: BodyScanTiming.Stage) {
    if diagnosticStage == next { return }
    endDiagnosticStage()
    diagnosticStage = next
    diagnosticStartedAt = ContinuousClock.now
  }

  private func endDiagnosticStage() {
    guard let diagnosticStage, let diagnosticStartedAt else { return }
    BodyScanTiming.record(diagnosticStage, duration: diagnosticStartedAt.duration(to: ContinuousClock.now))
    self.diagnosticStage = nil
    self.diagnosticStartedAt = nil
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
