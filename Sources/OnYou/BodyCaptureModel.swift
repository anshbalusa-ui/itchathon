import AVFoundation
import Foundation
import Observation
import OSLog
import RealityKit

@MainActor @Observable
final class BodyCaptureModel {
  enum Phase: Equatable {
    case setup, preparing, capturing, reconstructing, review, failed(String)
  }

  enum Recovery: Equatable {
    case retake, retryProcessing, missingViews([Double])
  }

  private(set) var recovery: Recovery?
  private(set) var phase = Phase.setup
  private var capture: BodyCaptureController?
  private(set) var progress: Double = 0
  private(set) var completedPasses = 0
  private(set) var calibration: AvatarScanCalibration?
  private(set) var modelURL: URL?
  private(set) var preparedScene: PreparedAvatarScene?
  private(set) var imageCount = 0
  private(set) var cameraStatus = BodyScanCameraStatus(mode: .initializing)
  private(set) var position = ScanPositionFeedback()
  private(set) var estimatedRemainingTime: TimeInterval?
  private(set) var hasBuildProgress = false
  private(set) var saveError: String?
  private static let logger = Logger(subsystem: "app.onyou", category: "BodyCapture")
  private static var activeWork = Set<URL>()
  private var archive: BodyCaptureArchive?
  var stage = "Aligning images"
  private var work: URL?
  private var reconstruction: PhotogrammetrySession?
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var diagnosticStage: BodyScanTiming.Stage?
  private var diagnosticStartedAt: ContinuousClock.Instant?


  static var isSupported: Bool { BodyCaptureController.supported && PhotogrammetrySession.isSupported }
  var captureDirectory: URL? { work?.appendingPathComponent("Images", isDirectory: true) }
  var captureID: UUID { generation }
  var captureSeed: BodyCaptureArchive? { archive }
  var requestedAngles: [Double] {
    if case .missingViews(let angles) = recovery { return angles }
    return []
  }
  var hasUnsavedCapture: Bool {
    archive != nil || phase == .review || cameraStatus.mode == .capturing
      || cameraStatus.mode == .finishing || cameraStatus.pendingStart
  }

  func cameraReady(_ controller: BodyCaptureController, directory: URL, captureID: UUID) {
    guard phase == .capturing, captureDirectory == directory, generation == captureID else {
      controller.stop()
      return
    }
    capture = controller
    cameraStatus.mode = .framing
  }

  func cameraUpdated(_ update: BodyCaptureUpdate, directory: URL, captureID: UUID) {
    guard phase == .capturing, captureDirectory == directory, generation == captureID,
          cameraStatus.mode != .finishing else { return }
    position = update.position
    cameraStatus.calibrated = update.calibrated
    cameraStatus.calibrationProgress = update.calibrationProgress
    cameraStatus.observedAt = update.observedAt
    cameraStatus.completedViews = update.completedViews
    cameraStatus.missingAngles = update.missingAngles
    cameraStatus.direction = update.direction
    cameraStatus.instruction = update.instruction
    if update.captureComplete {
      cameraStatus.mode = .finishing
      position = ScanPositionFeedback()
      beginDiagnosticStage(.captureFinalization)
      capture?.finishCapture()
    }
  }

  func cameraFinished(_ captured: BodyCaptureArchive, directory: URL, captureID: UUID) {
    guard phase == .capturing, captureDirectory == directory, generation == captureID else { return }
    guard captured.hasCoverage() else { fail(AvatarScanError.insufficientCoverage); return }
    capture?.stop()
    capture = nil
    archive = captured
    imageCount = captured.sampleCount
    completedPasses = 1
    position = ScanPositionFeedback()
    endDiagnosticStage()
    reconstruct()
  }

  func cameraFailed(_ error: Error, directory: URL, captureID: UUID) {
    guard phase == .capturing, captureDirectory == directory, generation == captureID else { return }
    if error as? BodyCaptureCameraError == .interrupted, archive != nil, !requestedAngles.isEmpty {
      fail(error, recovery: .missingViews(requestedAngles))
      return
    }
    fail(error)
  }

  func performCameraAction() {
    guard cameraStatus.canStart(now: ProcessInfo.processInfo.systemUptime), let capture else { return }
    let token = generation
    cameraStatus.pendingStart = true
    Task { [weak self] in
      let started = await capture.startScanning()
      guard let self, generation == token, phase == .capturing, cameraStatus.mode == .framing else { return }
      cameraStatus.pendingStart = false
      guard started else {
        cameraStatus.calibrated = false
        cameraStatus.instruction = "Keep iPhone steady."
        return
      }
      cameraStatus.mode = .capturing
      cameraStatus.instruction = "Hold there."
      beginDiagnosticStage(.bodyPass)
    }
  }

  func clearSaveError() { saveError = nil }


  func start() async {
    cancel()
    guard Self.isSupported else { fail(AvatarScanError.unsupported); return }
    phase = .preparing
    let token = generation
    let permission: Bool
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: permission = true
    case .notDetermined: permission = await AVCaptureDevice.requestAccess(for: .video)
    default: permission = false
    }
    guard generation == token, !Task.isCancelled else { return }
    guard permission else { fail(AvatarScanError.unavailableCamera); return }
    do {
      let root = URL.applicationSupportDirectory.appendingPathComponent("OnYouCaptureWork", isDirectory: true)
      try AvatarScanStore.prepareDirectory(root)
      let capacity = try FileManager.default.attributesOfFileSystem(forPath: root.path)[.systemFreeSize] as? NSNumber
      guard let capacity, capacity.int64Value >= 2_000_000_000 else { throw AvatarScanError.insufficientSpace }
      // Do not remove another scan's directory while a canceled native build is unwinding.
      for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        where UUID(uuidString: url.lastPathComponent) != nil && !Self.activeWork.contains(url.standardizedFileURL) {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isDirectory == true && values.isSymbolicLink != true { try FileManager.default.removeItem(at: url) }
      }
      let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try AvatarScanStore.prepareDirectory(directory)
      work = directory
      Self.activeWork.insert(directory.standardizedFileURL)
      let images = directory.appendingPathComponent("Images", isDirectory: true)
      try AvatarScanStore.prepareDirectory(images)
      cameraStatus = BodyScanCameraStatus(mode: .initializing)
      phase = .capturing
      beginDiagnosticStage(.framing)
    } catch { fail(error) }
  }


  func setCapturePromptVisible(_ visible: Bool) {
    guard phase == .capturing else { return }
    capture?.setPaused(visible)
    if visible { position = ScanPositionFeedback() }
  }

  func retryProcessing() {
    guard case .failed = phase, recovery == .retryProcessing, archive != nil, work != nil else { return }
    reconstruct()
  }

  func captureMissingViews() {
    guard case .failed = phase, case .missingViews = recovery, let archive, work != nil else { return }
    invalidateWork()
    cameraStatus = BodyScanCameraStatus(mode: .initializing)
    cameraStatus.direction = archive.direction
    cameraStatus.missingAngles = requestedAngles
    cameraStatus.completedViews = BodyCaptureTurn(direction: archive.direction, recoveringAngles: requestedAngles)
      .feedback(coverage: archive.coverage).completedViews
    phase = .capturing
    beginDiagnosticStage(.framing)
  }

  func suspend() {
    switch phase {
    case .reconstructing: fail(CaptureInterrupted(), recovery: .retryProcessing)
    case .capturing where archive != nil && !requestedAngles.isEmpty:
      fail(CaptureInterrupted(), recovery: .missingViews(requestedAngles))
    case .capturing, .preparing: fail(CaptureInterrupted())
    default: break
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
    invalidateWork()
    let pending = task
    task = nil
    if let work {
      if let pending {
        Task { await pending.value; Self.removeWork(work) }
      } else {
        Self.removeWork(work)
      }
    }
    archive = nil
    recovery = nil
    work = nil
    modelURL = nil
    calibration = nil
    preparedScene = nil
    completedPasses = 0
    imageCount = 0
    cameraStatus = BodyScanCameraStatus(mode: .initializing)
    position = ScanPositionFeedback()
    estimatedRemainingTime = nil
    hasBuildProgress = false
    saveError = nil
    progress = 0
    phase = .setup
  }

  private static func removeWork(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
    activeWork.remove(url.standardizedFileURL)
  }

  private func invalidateWork() {
    endDiagnosticStage()
    generation = UUID()
    task?.cancel()
    reconstruction?.cancel()
    reconstruction = nil
    capture?.stop()
    capture = nil
    position = ScanPositionFeedback()
  }

  private func fail(_ error: Error, recovery: Recovery = .retake) {
    Self.logger.error("Capture failed: \(error.localizedDescription, privacy: .private)")
    invalidateWork()
    self.recovery = recovery
    phase = .failed(error.localizedDescription)
  }

  private func missingViews(_ angles: [Double], in archive: BodyCaptureArchive, keeping ids: Set<Int>) {
    self.archive = archive.retaining(sampleIDs: ids)
    fail(AvatarScanError.insufficientCoverage, recovery: .missingViews(angles))
  }

  private func reconstruct() {
    guard let work, let archive, archive.hasCoverage() else { fail(AvatarScanError.insufficientCoverage); return }
    let previous = task
    invalidateWork()
    recovery = nil
    phase = .reconstructing
    progress = 0
    hasBuildProgress = false
    estimatedRemainingTime = nil
    stage = "Preparing your photos"
    let token = generation
    let build = work.appendingPathComponent("Build-\(token.uuidString)", isDirectory: true)
    task = Task { [weak self] in
      await previous?.value
      guard !Task.isCancelled, let self, generation == token else { return }
      var keepModel = false
      defer {
        if !keepModel { try? FileManager.default.removeItem(at: build) }
        if generation == token {
          task = nil
          reconstruction = nil
        }
      }
      do {
        let checkpoints = build.appendingPathComponent("Checkpoints", isDirectory: true)
        try AvatarScanStore.prepareDirectory(checkpoints)
        beginDiagnosticStage(.photoPreflight)
        let input = AvatarScanInput(imageURLs: archive.imageURLs, depthImageURLs: archive.depthImageURLs)
        imageCount = try input.validate(passes: completedPasses)
        let photos = try archive.makePhotogrammetryInput()
        try Task.checkCancellation()
        guard generation == token else { return }
        beginDiagnosticStage(.reconstruction)
        var configuration = PhotogrammetrySession.Configuration()
        configuration.checkpointDirectory = checkpoints
        configuration.isObjectMaskingEnabled = true
        configuration.featureSensitivity = .high
        configuration.sampleOrdering = .unordered
        let setup = Task.detached(priority: .userInitiated) {
          try Task.checkCancellation()
          let session = try PhotogrammetrySession(input: photos.samples, configuration: configuration)
          do {
            try photos.validateReads()
            try Task.checkCancellation()
          } catch {
            session.cancel()
            throw error
          }
          return session
        }
        let session = try await withTaskCancellationHandler {
          try await setup.value
        } onCancel: { setup.cancel() }
        guard generation == token, !Task.isCancelled else { session.cancel(); return }
        reconstruction = session
        let destination = build.appendingPathComponent("avatar.usdz")
        let modelRequest = PhotogrammetrySession.Request.modelFile(url: destination, detail: .reduced)
        try session.process(requests: [modelRequest, .poses])
        var rejected = Set<Int>()
        var producedFile = false
        var incomplete = false
        var processingError: Error?
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
          case .stitchingIncomplete: incomplete = true
          case .requestError(_, let error): processingError = processingError ?? error
          case .processingCancelled: throw CancellationError()
          case .processingComplete:
            try photos.validateReads()
            guard let usedPoses else {
              if let processingError { throw processingError }
              fail(CaptureAlignmentFailed())
              return
            }
            let poses = usedPoses.posesBySample.mapValues {
              BodyCaptureReconstructedPose(translation: $0.translation, rotation: $0.rotation)
            }
            switch archive.alignedCoverage(poses: poses, rejectedIDs: rejected) {
            case .missingAngles(let angles):
              missingViews(angles, in: archive, keeping: Set(poses.keys).subtracting(rejected))
              return
            case .invalid:
              fail(CaptureAlignmentFailed())
              return
            case .complete:
              guard !incomplete else { fail(CaptureAlignmentFailed()); return }
            }
            if let processingError { throw processingError }
            guard producedFile else { fail(CaptureAlignmentFailed()); return }
            imageCount = try input.validate(usedSampleIDs: Set(usedPoses.posesBySample.keys),
                                            urlsBySample: archive.urlsBySample, rejectedIDs: rejected,
                                            fullBodyImageURLs: archive.fullBodyImageURLs, passes: completedPasses)
            endDiagnosticStage()
            stage = "Checking your avatar"
            let prepared = try await PreparedAvatarScene.load(url: destination)
            try Task.checkCancellation()
            guard generation == token else { return }
            keepModel = true
            if let timings = prepared.loadTimings {
              BodyScanTiming.record(.textureValidation,duration: timings.validation)
              BodyScanTiming.record(.avatarLoading,duration: timings.scene)
            }
            calibration = prepared.calibration
            preparedScene = prepared
            modelURL = destination
            reconstruction = nil
            progress = 1
            self.archive = nil
            recovery = nil
            // A usable draft needs only its validated model, not private source images.
            if let images = captureDirectory { try? FileManager.default.removeItem(at: images) }
            try? FileManager.default.removeItem(at: checkpoints)
            phase = .review
            return
          default: break
          }
        }
        if phase != .review { throw AvatarScanError.invalidModel }
      } catch {
        guard generation == token else { return }
        let needsRetake = error is BodyCaptureArchiveError || error is AvatarScanError
        fail(error, recovery: needsRetake ? .retake : .retryProcessing)
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
  var errorDescription: String? { "The scan was interrupted. Return to On You to continue." }
}

private struct CaptureAlignmentFailed: LocalizedError {
  var errorDescription: String? { "The views didn’t align. Keep arms and torso together while turning." }
}
