import AVFoundation
import Foundation
import Observation
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
  var referenceHeightCM: Double = 175
  var stage = "Aligning images"
  private var work: URL?
  private var reconstruction: PhotogrammetrySession?
  private var task: Task<Void, Never>?
  private var generation = UUID()

  static var isSupported: Bool { ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported }

  var canFinish: Bool {
    guard let capture else { return false }
    return Self.hasCoverage(images: capture.numberOfShotsTaken, passes: completedPasses)
      && capture.cameraTracking == .normal && !capture.isPaused && !trackingInterrupted
      && capture.feedback.isDisjoint(with: [.objectTooClose, .objectTooFar, .environmentTooDark,
                                            .environmentLowLight, .movingTooFast, .outOfFieldOfView, .objectNotDetected])
  }

  static func hasCoverage(images: Int, passes: Int) -> Bool { images >= 60 && passes >= 2 }

  func start() async {
    guard Self.isSupported else { phase = .failed(AvatarScanError.unsupported.localizedDescription); return }
    guard BodyMeasurementField.height.range.contains(referenceHeightCM) else {
      phase = .failed("Enter your measured height between 120 and 220 cm."); return
    }
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
      configuration.isOverCaptureEnabled = true
      let session = ObjectCaptureSession()
      capture = session
      phase = .capturing
      session.start(imagesDirectory: images, configuration: configuration)
    } catch { fail(error) }
  }

  func stateChanged(_ state: ObjectCaptureSession.CaptureState) {
    guard phase == .capturing else { return }
    switch state {
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
    guard completed, phase == .capturing else { return }
    completedPasses += 1
  }

  func nextPass() {
    guard let capture, capture.userCompletedScanPass else { return }
    capture.beginNewScanPass()
  }

  func finish() { if canFinish { capture?.finish() } }

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
      store.error = error.localizedDescription
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
    progress = 0
    phase = .setup
  }

  private func fail(_ error: Error) {
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
            if fraction.isFinite { progress = min(1, max(0, fraction)) }
          case .requestProgressInfo(_, let info):
            if let value = info.processingStage { stage = title(value) }
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
            _ = try AvatarScanStore.digest(destination)
            let result = try ScannedAvatarGeometry.load(url: destination, referenceHeightCM: referenceHeightCM)
            calibration = result.calibration
            modelURL = destination
            reconstruction = nil
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
    case .preProcessing: "Checking images"
    case .imageAlignment: "Aligning views"
    case .pointCloudGeneration: "Reconstructing depth"
    case .meshGeneration: "Building surface"
    case .textureMapping: "Adding photo texture"
    case .optimization: "Finishing avatar"
    @unknown default: "Building avatar"
    }
  }
}

private struct CaptureInterrupted: LocalizedError {
  var errorDescription: String? { "The scan was interrupted. Start again so all views share the same tracking and scale." }
}
