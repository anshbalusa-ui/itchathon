import CoreMotion
import RealityKit
import SwiftUI
import XCTest
@testable import FitCheck

@MainActor
final class BodyCaptureModelTests: XCTestCase {
  func testCountdownArmsBeforeFramingWaitsOnceAndRequiresFreshEvidence() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    scan.model.performCameraAction()
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
    scan.update(calibrated: true)
    XCTAssertEqual(scan.controller.startRequests, 0)
    XCTAssertEqual(scan.controller.finishRequests, 0)
    try await scan.finishCountdown()
    XCTAssertEqual(scan.model.cameraStatus.start, .waitingForFraming)
    XCTAssertEqual(scan.clock.waitCount, 5)
    XCTAssertEqual(scan.controller.startRequests, 0)

    scan.clock.now += 30
    for _ in 0..<8 { scan.update(calibrated: true, observedAt: scan.clock.now - 0.61) }
    scan.update(calibrated: true, observedAt: scan.clock.now + 0.1)
    scan.update(calibrated: false)
    XCTAssertEqual(scan.model.cameraStatus.start, .waitingForFraming)
    XCTAssertEqual(scan.clock.waitCount, 5)
    XCTAssertEqual(scan.controller.startRequests, 0)
    scan.update(calibrated: true)
    try await eventually { scan.controller.startRequests == 1 }
    for _ in 0..<8 { scan.update(calibrated: true) }
    XCTAssertEqual(scan.controller.startRequests, 1)
    XCTAssertEqual(scan.model.cameraStatus.start, .starting)
    scan.controller.completeStart(true)
    try await eventually { scan.model.cameraStatus.mode == .capturing }
    XCTAssertEqual(scan.model.cameraStatus.start, .idle)
    XCTAssertEqual(scan.clock.waitCount, 5)
  }

  func testCanceledCountdownCannotOverwriteRearmedCountdownWhenOldTickReturns() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    scan.model.performCameraAction()
    try await eventually { scan.clock.pendingCount == 1 }
    scan.model.performCameraAction()
    XCTAssertEqual(scan.model.cameraStatus.start, .idle)
    scan.model.performCameraAction()
    try await eventually { scan.clock.pendingCount == 2 }
    scan.clock.advanceNext() // Deliberately noncooperative old sleep completes after cancellation.
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
    XCTAssertEqual(scan.controller.startRequests, 0)
    try await scan.finishCountdown()
    scan.update(calibrated: true)
    try await eventually { scan.controller.startRequests == 1 }
    scan.controller.completeStart(true)
    try await eventually { scan.model.cameraStatus.mode == .capturing }
  }

  func testCancelDuringFramingWaitCannotStartOnLaterCameraUpdates() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    scan.model.performCameraAction()
    try await scan.finishCountdown()
    scan.model.performCameraAction()
    scan.update(calibrated: true)
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(scan.model.cameraStatus.start, .idle)
    XCTAssertEqual(scan.controller.startRequests, 0)
    scan.model.performCameraAction()
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
  }

  func testPromptOrInactivePauseInvalidatesCountdownAndFramingWait() async throws {
    for waitForFraming in [false, true] {
      let scan = try CaptureHarness()
      defer { scan.close() }
      try await scan.begin()
      scan.model.performCameraAction()
      if waitForFraming { try await scan.finishCountdown() }
      else { try await eventually { scan.clock.pendingCount == 1 } }
      scan.model.setCapturePromptVisible(true, captureID: scan.model.captureID)
      XCTAssertTrue(scan.controller.paused)
      scan.clock.cancelPending()
      scan.update(calibrated: true)
      scan.model.performCameraAction()
      for _ in 0..<20 { await Task.yield() }
      XCTAssertEqual(scan.model.cameraStatus.start, .idle)
      XCTAssertEqual(scan.controller.startRequests, 0)
      scan.model.setCapturePromptVisible(false, captureID: scan.model.captureID)
      scan.update(calibrated: true)
      XCTAssertFalse(scan.controller.paused)
      XCTAssertEqual(scan.model.cameraStatus.start, .idle)
      XCTAssertEqual(scan.controller.startRequests, 0)
    }
  }

  func testControllerArrivingAfterPauseInheritsPauseUntilDismissal() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin(attachController: false)
    let captureID = scan.model.captureID
    scan.model.setCapturePromptVisible(true, captureID: captureID)
    scan.attachController()
    XCTAssertTrue(scan.controller.paused, "A late native controller must inherit the pending pause.")
    scan.model.performCameraAction()
    XCTAssertEqual(scan.model.cameraStatus.start, .idle)
    XCTAssertEqual(scan.controller.startRequests, 0)
    scan.model.setCapturePromptVisible(false, captureID: captureID)
    XCTAssertFalse(scan.controller.paused)
  }

  func testNativeStartResultIsReconciledWhilePromptIsPaused() async throws {
    for started in [false, true] {
      let scan = try CaptureHarness()
      defer { scan.close() }
      try await scan.begin()
      try await scan.requestNativeStart()
      scan.model.setCapturePromptVisible(true, captureID: scan.model.captureID)
      XCTAssertTrue(scan.controller.paused)
      XCTAssertEqual(scan.model.cameraStatus.start, .starting)
      scan.controller.completeStart(started)
      try await eventually { scan.model.cameraStatus.start != .starting }
      XCTAssertEqual(scan.model.cameraStatus.mode, started ? .capturing : .framing)
      XCTAssertEqual(scan.model.cameraStatus.start, .idle)
      XCTAssertTrue(scan.controller.paused)
      scan.model.setCapturePromptVisible(false, captureID: scan.model.captureID)
      XCTAssertFalse(scan.controller.paused)
      XCTAssertEqual(scan.controller.startRequests, 1)
      if !started { XCTAssertFalse(scan.model.cameraStatus.calibrated) }
    }
  }

  func testNativeRefusalWaitsForFreshCalibrationWithoutRepeatingCountdown() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.requestNativeStart()
    scan.controller.completeStart(false)
    try await eventually { scan.model.cameraStatus.start == .waitingForFraming }
    XCTAssertFalse(scan.model.cameraStatus.calibrated)
    let previousObservation = scan.clock.now
    scan.clock.now += 1
    scan.update(calibrated: true, observedAt: previousObservation)
    XCTAssertEqual(scan.controller.startRequests, 1)
    scan.update(calibrated: true)
    try await eventually { scan.controller.startRequests == 2 }
    XCTAssertEqual(scan.clock.waitCount, 5)
    scan.controller.completeStart(true)
    try await eventually { scan.model.cameraStatus.mode == .capturing }
  }

  func testOldNativeStartCannotClearTheNewGenerationsPendingCountdown() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.requestNativeStart()
    let old = scan.controller
    let oldID = scan.model.captureID
    try await scan.begin()
    XCTAssertNotEqual(scan.model.captureID, oldID)
    XCTAssertTrue(old.stopped)
    scan.model.performCameraAction()
    try await eventually { scan.clock.pendingCount == 1 }
    old.completeStart(true)
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(scan.model.cameraStatus.mode, .framing)
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
    try await scan.finishCountdown()
    scan.update(calibrated: true)
    try await eventually { scan.controller.startRequests == 1 }
    scan.controller.completeStart(true)
    try await eventually { scan.model.cameraStatus.mode == .capturing }
  }

  func testOldCameraAndPauseCallbacksCannotChangeANewAttempt() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    let oldImages = scan.images
    let oldID = scan.model.captureID
    let archive = try metadataArchive(in: oldImages)
    try await scan.begin()
    let currentID = scan.model.captureID
    let obsolete = ControlledBodyCapture()
    scan.model.cameraReady(obsolete, directory: oldImages, captureID: oldID)
    scan.model.cameraUpdated(update(at: scan.clock.now, calibrated: true, complete: true), directory: oldImages, captureID: oldID)
    scan.model.cameraFinished(archive, directory: oldImages, captureID: oldID)
    scan.model.cameraFailed(ScriptedCaptureFailure(), directory: oldImages, captureID: oldID)
    scan.model.setCapturePromptVisible(true, captureID: oldID)
    XCTAssertTrue(obsolete.stopped)
    XCTAssertFalse(scan.controller.paused)
    scan.model.setCapturePromptVisible(true, captureID: currentID)
    scan.model.setCapturePromptVisible(false, captureID: oldID)
    XCTAssertTrue(scan.controller.paused, "An old view must not resume the current pause.")
    XCTAssertEqual(scan.model.phase, .capturing)
    XCTAssertEqual(scan.model.cameraStatus.mode, .framing)
    XCTAssertEqual(scan.model.captureID, currentID)
    XCTAssertEqual(scan.controller.finishRequests, 0)
    scan.model.setCapturePromptVisible(false, captureID: currentID)
    scan.model.performCameraAction()
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
  }

  func testBackgroundDuringNativeStartFailsClosedAndLateCompletionCannotResume() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.requestNativeStart()
    let oldID = scan.model.captureID
    scan.model.suspend()
    guard case .failed = scan.model.phase else { return XCTFail("Backgrounded capture must fail closed.") }
    XCTAssertTrue(scan.controller.stopped)
    XCTAssertNotEqual(scan.model.captureID, oldID)
    scan.controller.completeStart(true)
    scan.model.setCapturePromptVisible(false, captureID: oldID)
    scan.model.performCameraAction()
    for _ in 0..<20 { await Task.yield() }
    guard case .failed = scan.model.phase else { return XCTFail("Late completion revived capture.") }
    XCTAssertEqual(scan.model.cameraStatus.start, .idle)
    XCTAssertNil(scan.model.modelURL)
    XCTAssertEqual(scan.controller.startRequests, 1)
  }

  func testDuplicateCompletionFinalizesOnceAndCanceledProcessingCannotPublish() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.startCapturing()
    let images = scan.images
    let captureID = scan.model.captureID
    let captured = try metadataArchive(in: images)
    scan.update(calibrated: false, complete: true)
    scan.update(calibrated: false, complete: true)
    XCTAssertEqual(scan.controller.finishRequests, 1)
    XCTAssertEqual(scan.model.cameraStatus.mode, .finishing)
    scan.model.cameraFinished(captured, directory: images, captureID: captureID)
    XCTAssertEqual(scan.model.phase, .reconstructing)
    let processingID = scan.model.captureID
    scan.model.cameraFinished(captured, directory: images, captureID: captureID)
    XCTAssertEqual(scan.model.captureID, processingID)
    scan.model.cancel()
    try await eventually { !FileManager.default.fileExists(atPath: images.deletingLastPathComponent().path) }
    XCTAssertEqual(scan.model.phase, .setup)
    XCTAssertNil(scan.model.modelURL)
    XCTAssertNil(scan.model.preparedScene)
    XCTAssertNil(scan.model.captureSeed)
  }

  func testRepeatedRecoveryRetainsAdmittedSamplesDirectionAndNextID() async throws {
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.startCapturing()
    let original = try metadataArchive(in: scan.images, direction: -1)
    scan.finishCapture(original)
    let firstProcessingID = scan.model.captureID
    let keep = Set(original.samples.map(\.sampleID)).subtracting(25...30)
    let retained = original.retaining(sampleIDs: keep)
    let missing = retained.coverage.missingAngles()
    XCTAssertFalse(missing.isEmpty)
    scan.model.missingViews(missing, in: original, keeping: keep, captureID: firstProcessingID)
    XCTAssertEqual(scan.model.recovery, .missingViews(missing))
    scan.model.captureMissingViews()
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
    XCTAssertEqual(scan.model.captureSeed?.direction, -1)
    XCTAssertEqual(Set(scan.model.captureSeed?.samples.map(\.sampleID) ?? []), keep)
    XCTAssertEqual(scan.model.captureSeed?.nextSampleID, original.nextSampleID)
    scan.attachController()
    try await scan.finishCountdown()
    scan.update(calibrated: true)
    try await eventually { scan.controller.startRequests == 1 }
    scan.controller.completeStart(true)
    try await eventually { scan.model.cameraStatus.mode == .capturing }
    let recovered = try metadataArchive(in: scan.images, direction: -1, replacing: Set(25...30), replacementStart: 70, nextID: 90)
    scan.finishCapture(recovered)
    let secondProcessingID = scan.model.captureID
    let secondKeep = Set(recovered.samples.map(\.sampleID)).subtracting(10...13)
    let secondMissing = recovered.retaining(sampleIDs: secondKeep).coverage.missingAngles()
    XCTAssertFalse(secondMissing.isEmpty)
    scan.model.missingViews(secondMissing, in: recovered, keeping: secondKeep, captureID: secondProcessingID)
    scan.model.captureMissingViews()
    let recoveryID = scan.model.captureID
    scan.model.missingViews(missing, in: original, keeping: keep, captureID: firstProcessingID)
    XCTAssertEqual(scan.model.captureID, recoveryID)
    XCTAssertEqual(scan.model.requestedAngles, secondMissing)
    XCTAssertEqual(scan.model.captureSeed?.direction, -1)
    XCTAssertEqual(Set(scan.model.captureSeed?.samples.map(\.sampleID) ?? []), secondKeep)
    XCTAssertTrue(Set(70...75).isSubset(of: secondKeep))
    XCTAssertEqual(scan.model.captureSeed?.nextSampleID, 90)
    XCTAssertEqual(scan.model.cameraStatus.start, .countdown(5))
    XCTAssertEqual(scan.model.completedPasses, 1)
  }

  func testCanceledNativeSetupKeepsWorkUntilUnwindAndIgnoresLateFailure() async throws {
    let construction = ControlledSessionConstruction(blocked: true)
    let scan = try CaptureHarness(construction: construction)
    defer { scan.close() }
    try await scan.begin()
    try await scan.startCapturing()
    let oldWork = scan.images.deletingLastPathComponent()
    scan.finishCapture(try metadataArchive(in: scan.images))
    try await eventually { construction.requestCount == 1 }
    scan.model.cancel()
    XCTAssertTrue(FileManager.default.fileExists(atPath: oldWork.path),
                  "Native construction still owns its input until it unwinds.")
    try await scan.begin()
    let replacementID = scan.model.captureID
    construction.releaseFailure()
    try await eventually { !FileManager.default.fileExists(atPath: oldWork.path) }
    XCTAssertEqual(scan.model.captureID, replacementID)
    XCTAssertEqual(scan.model.phase, .capturing)
    XCTAssertEqual(scan.model.cameraStatus.mode, .framing)
    XCTAssertNil(scan.model.modelURL)
    XCTAssertEqual(scan.controller.startRequests, 0)
  }

  #if DEBUG
  func testFailedReconstructionAndDiscardLeaveTheSavedAvatarUnchanged() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let saved = try XCTUnwrap(fixture.scans.asset)
    let originalHash = try AvatarScanStore.digest(saved.url)
    let scan = try CaptureHarness()
    defer { scan.close() }
    try await scan.begin()
    try await scan.startCapturing()
    // Session construction deliberately fails; the real model handles failure/retry.
    // The simulator must never construct an unsupported native session.
    scan.finishCapture(try metadataArchive(in: scan.images))
    try await eventually { if case .failed = scan.model.phase { return true }; return false }
    XCTAssertEqual(scan.model.recovery, .retryProcessing)
    scan.model.retryProcessing()
    try await eventually {
      if case .failed = scan.model.phase { return scan.construction.requestCount == 2 }
      return false
    }
    XCTAssertEqual(scan.model.recovery, .retryProcessing)
    XCTAssertNil(scan.model.modelURL)
    XCTAssertNil(scan.model.preparedScene)
    XCTAssertFalse(scan.model.save(to: fixture.scans))
    XCTAssertEqual(fixture.scans.asset, saved)
    XCTAssertEqual(try AvatarScanStore.digest(saved.url), originalHash)
    scan.model.cancel()
    XCTAssertFalse(scan.model.save(to: fixture.scans))
    XCTAssertEqual(fixture.scans.asset, saved)
    let repository = saved.url.deletingLastPathComponent().deletingLastPathComponent()
    XCTAssertEqual(AvatarScanStore(directory: repository).asset, saved)
    XCTAssertEqual(try AvatarScanStore.digest(saved.url), saved.record.sha256)
  }
  #endif

  func testLatePreparationCannotReplaceNewAttemptAndDiscardsItsOwnedDirectory() async throws {
    for oldFails in [false, true] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try AvatarScanStore.prepareDirectory(root)
      let preparation = ControlledPreparation()
      let model = BodyCaptureModel(prepareCapture: { try await preparation.prepare() })
      defer { model.cancel(); preparation.cancelPending(); try? FileManager.default.removeItem(at: root) }
      let old = Task { await model.start() }
      try await eventually { preparation.pending.count == 1 }
      let current = Task { await model.start() }
      try await eventually { preparation.pending.count == 2 }
      let newWork = root.appendingPathComponent(UUID().uuidString)
      try AvatarScanStore.prepareDirectory(newWork)
      preparation.pending.removeLast().resume(returning: newWork)
      await current.value
      let currentID = model.captureID
      let oldWork = root.appendingPathComponent(UUID().uuidString)
      if oldFails { preparation.pending.removeFirst().resume(throwing: ScriptedCaptureFailure()) }
      else {
        try AvatarScanStore.prepareDirectory(oldWork)
        preparation.pending.removeFirst().resume(returning: oldWork)
      }
      await old.value
      XCTAssertEqual(model.captureID, currentID)
      XCTAssertEqual(model.phase, .capturing)
      XCTAssertEqual(model.captureDirectory, newWork.appendingPathComponent("Images", isDirectory: true))
      XCTAssertFalse(FileManager.default.fileExists(atPath: oldWork.path))
      XCTAssertTrue(FileManager.default.fileExists(atPath: newWork.path))
    }
  }

  func testCaptureSurfaceReportsInitialInactiveAndDisappearancePause() async throws {
    var pauses: [Bool] = []
    let root = BodyScanCameraView(status: BodyScanCameraStatus(mode: .framing), close: {}, performAction: {},
                                  pauseCapture: { pauses.append($0) }) {
      Color(white: 0.18).overlay { Text("Camera-free lifecycle fixture").foregroundStyle(.white) }
    }
    .environment(\.scenePhase, .inactive)
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
    let host = UIHostingController(rootView: root)
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(pauses.last, true, "Initial inactive state must be applied without waiting for onChange.")
    host.view.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
      host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }
    let attachment = XCTAttachment(image: image)
    attachment.name = "capture-initial-inactive-camera-free-fixture"
    attachment.lifetime = .keepAlways
    add(attachment)
    pauses.removeAll()
    window.rootViewController = UIViewController()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertEqual(pauses.last, true, "Removing the capture surface must pause its native session.")
  }
}

// Controlled native outcomes establish coordinator ordering only, never camera evidence.
@MainActor
private final class ControlledBodyCapture: BodyCaptureControlling {
  private(set) var paused = false
  private(set) var stopped = false
  private(set) var startRequests = 0
  private(set) var finishRequests = 0
  private var starts: [CheckedContinuation<Bool, Never>] = []

  func startScanning() async -> Bool {
    startRequests += 1
    return await withCheckedContinuation { starts.append($0) }
  }
  func completeStart(_ started: Bool) { starts.removeFirst().resume(returning: started) }
  func finishCapture() { finishRequests += 1 }
  func setPaused(_ paused: Bool) { self.paused = paused }
  func stop() { stopped = true }
  func completePending() {
    let pending = starts
    starts.removeAll()
    for start in pending { start.resume(returning: false) }
  }
}

@MainActor
private final class CaptureClock {
  var now = 100.0
  private(set) var waitCount = 0
  private var pending: [CheckedContinuation<Void, Error>] = []
  var pendingCount: Int { pending.count }
  func wait() async throws {
    waitCount += 1
    try await withCheckedThrowingContinuation { pending.append($0) }
  }
  func advanceNext() {
    now += 1
    pending.removeFirst().resume()
  }
  func cancelPending() {
    let ticks = pending
    pending.removeAll()
    for tick in ticks { tick.resume(throwing: CancellationError()) }
  }
}

// The production factory returns Apple's concrete session. Tests can delay/throw
// without manufacturing a native session or consuming unsupported simulator APIs.
private final class ControlledSessionConstruction: @unchecked Sendable {
  private let condition = NSCondition()
  private var blocked: Bool
  private var requests = 0
  init(blocked: Bool = false) { self.blocked = blocked }
  var requestCount: Int {
    condition.lock()
    defer { condition.unlock() }
    return requests
  }
  func make(_: BodyPhotogrammetryInput, _: PhotogrammetrySession.Configuration) throws -> PhotogrammetrySession {
    condition.lock()
    requests += 1
    while blocked { condition.wait() }
    condition.unlock()
    throw ScriptedCaptureFailure()
  }
  func releaseFailure() {
    condition.lock()
    blocked = false
    condition.broadcast()
    condition.unlock()
  }
}

@MainActor
private final class ControlledPreparation {
  var pending: [CheckedContinuation<URL, Error>] = []
  func prepare() async throws -> URL {
    try await withCheckedThrowingContinuation { pending.append($0) }
  }
  func cancelPending() {
    let preparations = pending
    pending.removeAll()
    for preparation in preparations { preparation.resume(throwing: CancellationError()) }
  }
}

@MainActor
private final class CaptureHarness {
  let root: URL
  let clock = CaptureClock()
  let model: BodyCaptureModel
  let construction: ControlledSessionConstruction
  private(set) var controller = ControlledBodyCapture()
  private var controllers: [ControlledBodyCapture] = []
  var images: URL { model.captureDirectory! }

  init(construction: ControlledSessionConstruction = ControlledSessionConstruction()) throws {
    self.construction = construction
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    self.root = root
    try AvatarScanStore.prepareDirectory(root)
    let clock = self.clock
    model = BodyCaptureModel(prepareCapture: {
      let work = root.appendingPathComponent(UUID().uuidString)
      try AvatarScanStore.prepareDirectory(work)
      return work
    }, countdownTick: { try await clock.wait() }, uptime: { clock.now },
       makeSession: { try construction.make($0, $1) })
  }
  func begin(attachController: Bool = true) async throws {
    await model.start()
    XCTAssertEqual(model.phase, .capturing)
    _ = try XCTUnwrap(model.captureDirectory)
    if attachController { self.attachController() }
  }
  func attachController() {
    controller = ControlledBodyCapture()
    controllers.append(controller)
    model.cameraReady(controller, directory: images, captureID: model.captureID)
  }
  func update(calibrated: Bool, observedAt: TimeInterval? = nil, complete: Bool = false) {
    model.cameraUpdated(FitCheck.BodyCaptureUpdate(position: ScanPositionFeedback(), calibrationProgress: calibrated ? 1 : 0,
      calibrated: calibrated, observedAt: observedAt ?? clock.now, completedViews: [], missingAngles: [], direction: 1,
      captureComplete: complete, instruction: "Controlled coordinator observation"), directory: images, captureID: model.captureID)
  }
  func finishCountdown() async throws {
    for seconds in stride(from: 4, through: 0, by: -1) {
      try await eventually { self.clock.pendingCount > 0 }
      clock.advanceNext()
      try await eventually {
        seconds > 0 ? self.model.cameraStatus.start == .countdown(seconds) : self.model.cameraStatus.start == .waitingForFraming
      }
    }
  }
  func requestNativeStart() async throws {
    model.performCameraAction()
    try await finishCountdown()
    update(calibrated: true)
    try await eventually { self.controller.startRequests == 1 }
    XCTAssertEqual(model.cameraStatus.start, .starting)
  }
  func startCapturing() async throws {
    try await requestNativeStart()
    controller.completeStart(true)
    try await eventually { self.model.cameraStatus.mode == .capturing }
  }
  func finishCapture(_ archive: BodyCaptureArchive) {
    update(calibrated: false, complete: true)
    model.cameraFinished(archive, directory: images, captureID: model.captureID)
    XCTAssertEqual(model.phase, .reconstructing)
  }
  func close() {
    model.cancel()
    construction.releaseFailure()
    clock.cancelPending()
    for controller in controllers { controller.completePending() }
    try? FileManager.default.removeItem(at: root)
  }
}

private func update(at time: TimeInterval, calibrated: Bool, complete: Bool = false) -> BodyCaptureUpdate {
  BodyCaptureUpdate(position: ScanPositionFeedback(), calibrationProgress: calibrated ? 1 : 0,
                    calibrated: calibrated, observedAt: time, completedViews: [], missingAngles: [], direction: 1,
                    captureComplete: complete, instruction: "Obsolete controlled observation")
}

// No photo, native pose or successful reconstructed model is fabricated. This archive
// supplies metadata for scripted callback transitions and deliberately fails real preflight.
private func metadataArchive(in images: URL, direction: Int = 1, replacing: Set<Int> = [],
                             replacementStart: Int = 60, nextID: Int = 60) throws -> BodyCaptureArchive {
  var samples: [BodyCaptureStoredSample] = []
  var coverage = BodyCaptureCoverage()
  var replacement = replacementStart
  for index in 0..<60 {
    let id: Int
    if replacing.contains(index) { id = replacement; replacement += 1 }
    else { id = index }
    let angle = Double(direction * index) * 2 * .pi / 60
    let fullBody = BodyCaptureCoverage.distance(angle, 0) <= .pi / 12
    let image = images.appendingPathComponent("body-\(id).jpg")
    guard coverage.record(sampleID: id, imageURL: image, azimuth: angle, fullBody: fullBody) else {
      throw ScriptedCaptureFailure()
    }
    samples.append(BodyCaptureStoredSample(sampleID: id, imageURL: image,
      depthURL: images.appendingPathComponent("body-\(id).depth"), maskURL: images.appendingPathComponent("body-\(id).mask"),
      azimuth: angle, fullBody: fullBody, gravity: CMAcceleration(x: 0, y: -1, z: 0)))
  }
  let archive = BodyCaptureArchive(samples: samples, coverage: coverage, direction: direction, nextSampleID: nextID)
  XCTAssertTrue(archive.hasCoverage())
  return archive
}

@MainActor
private func eventually(file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(3))
  while !condition() {
    guard ContinuousClock.now < deadline else {
      XCTFail("Coordinator did not reach the expected controlled state.", file: file, line: line)
      throw ScriptedCaptureFailure()
    }
    await Task.yield()
  }
}

private struct ScriptedCaptureFailure: Error {}
