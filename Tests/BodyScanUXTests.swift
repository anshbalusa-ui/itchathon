import SwiftUI
import XCTest
@testable import FitCheck

final class BodyScanUXTests: XCTestCase {
  func testPhotoLimitOffersRecoveryAndCanStillAcceptAFinalCompletedPass() {
    var status = BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 200,
                                     trackingNormal: false, issue: "Move closer.", maximumShots: 200)
    XCTAssertTrue(status.exhaustedCaptureCapacity)
    XCTAssertEqual(status.action, .retakeScan)
    XCTAssertTrue(status.actionEnabled)
    XCTAssertTrue(status.instruction.contains("photo limit"))
    // A late pass-completion update must still be allowed to make this capture usable.
    status.completedPasses = 2
    status.passComplete = true
    XCTAssertFalse(status.exhaustedCaptureCapacity)
    XCTAssertEqual(status.action, .buildAvatar)
    XCTAssertTrue(status.actionEnabled)
    status.maximumShots = nil
    XCTAssertFalse(status.exhaustedCaptureCapacity)
  }

  func testCameraActionsFollowActualCoverageAndExplainBlockedStates() {
    var status = BodyScanCameraStatus(mode: .framing)
    XCTAssertEqual(status.action, .findPerson)
    status.pendingAction = .findPerson
    XCTAssertFalse(status.actionEnabled)
    XCTAssertEqual(status.pendingTitle, "Finding person…")
    status.pendingAction = nil
    status.selectionHint = "Include the floor and try again."
    XCTAssertTrue(status.actionEnabled)
    XCTAssertEqual(status.instruction, status.selectionHint)

    status = BodyScanCameraStatus(mode: .capturing, shots: 30)
    XCTAssertNil(status.action)
    XCTAssertFalse(status.awaitsNextStep)
    status.completedPasses = 1
    status.passComplete = true
    XCTAssertEqual(status.action, .nextPass)
    XCTAssertEqual(status.actionTitle, "Continue to details")
    status.completedPasses = 2
    XCTAssertEqual(status.action, .nextPass)
    status.shots = 60
    XCTAssertEqual(status.action, .buildAvatar)
    status.issue = "Move more slowly."
    XCTAssertTrue(status.actionEnabled)
    XCTAssertTrue(status.instruction.contains("Stop walking"))
    status.issue = nil
    status.trackingNormal = false
    XCTAssertTrue(status.actionEnabled)
    status = BodyScanCameraStatus(mode: .finishing, issue: "Capture is paused.")
    XCTAssertNil(status.action)
    XCTAssertEqual(status.step, .build)
    XCTAssertTrue(status.instruction.contains("being saved"))
  }

  func testCompletedCircleRemainsActionableDespiteLiveCameraWarnings() {
    for issue in ["Move a little closer.", "Slow down.", "Capture is paused."] {
      var status = BodyScanCameraStatus(mode: .capturing, completedPasses: 1,
                                       shots: 30, passComplete: true,
                                       trackingNormal: false, issue: issue)
      XCTAssertEqual(status.action, .nextPass)
      XCTAssertTrue(status.actionEnabled)
      XCTAssertTrue(status.instruction.contains("Stop walking"))
      XCTAssertNotEqual(status.instruction, issue)
      status.completedPasses = 2
      status.shots = 60
      XCTAssertEqual(status.action, .buildAvatar)
      XCTAssertTrue(status.actionEnabled)
      status.pendingAction = .buildAvatar
      XCTAssertFalse(status.actionEnabled)
    }
  }

  func testWarningsStillBlockFramingAndStartingCapture() {
    for mode in [BodyScanCameraStatus.Mode.framing, .selecting] {
      let status = BodyScanCameraStatus(mode: mode, issue: "Find brighter light.")
      XCTAssertFalse(status.actionEnabled)
      XCTAssertEqual(status.instruction, "Find brighter light.")
    }
  }

  func testFeedbackPrecedenceAndDirectionalEvidenceAreConservative() {
    let mode = BodyScanCameraStatus.Mode.capturing
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [.environmentLowLight,.movingTooFast],mode: mode,capturePaused: false,trackingNormal: false),.lighting)
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [.objectTooClose,.outOfFieldOfView],mode: mode,capturePaused: false,trackingNormal: true),.tooClose)
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [.objectTooFar],mode: mode,capturePaused: false,trackingNormal: true),.tooFar)
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [.outOfFieldOfView],mode: mode,capturePaused: false,trackingNormal: true),.framing)
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [.outOfFieldOfView],mode: mode,capturePaused: false,trackingNormal: false),.tracking)
    XCTAssertEqual(BodyScanCameraStatus.guidance(for: [],mode: mode,capturePaused: true,trackingNormal: true),.paused)
  }

  func testPassProgressExplainsBodyDetailTransitionsAndCapacityRecovery() {
    let firstPass = BodyScanCameraStatus(mode: .capturing, completedPasses: 1,
                                        shots: 31, passComplete: true)
    XCTAssertEqual(firstPass.step, .detail)
    XCTAssertEqual(firstPass.currentPass,1,"A paused completed body circle must not be counted as the active detail circle")
    XCTAssertEqual(firstPass.action,.nextPass)
    XCTAssertTrue(firstPass.actionEnabled)
    let detailCapture = BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 45)
    XCTAssertEqual(detailCapture.step,.detail)
    XCTAssertEqual(detailCapture.currentPass,2,"The second active circle must agree with the Detail stage")
    XCTAssertFalse(detailCapture.awaitsNextStep)

    let secondPass = BodyScanCameraStatus(mode: .capturing, completedPasses: 2,
                                         shots: 58, passComplete: true)
    XCTAssertEqual(secondPass.step, .detail)
    XCTAssertEqual(secondPass.currentPass,2)
    XCTAssertEqual(secondPass.action,.nextPass)
    XCTAssertTrue(secondPass.actionEnabled)

    let capacity = BodyScanCameraStatus(mode: .capturing, completedPasses: 1,
                                        shots: 200, maximumShots: 200)
    XCTAssertEqual(capacity.action, .retakeScan)
  }

  func testStageDiagnosticConversionUsesMonotonicDurationOnly() {
    XCTAssertEqual(BodyScanTiming.seconds(for: .milliseconds(1_500)), 1.5, accuracy: 0.000_001)
    XCTAssertEqual(BodyScanTiming.seconds(for: .seconds(-1)), 0)
    XCTAssertNil(BodyScanTiming.buildProgress(current: 0, fraction: .nan))
    XCTAssertNil(BodyScanTiming.buildProgress(current: 0, fraction: .infinity))
    XCTAssertEqual(BodyScanTiming.buildProgress(current: 0, fraction: -1), 0)
    XCTAssertEqual(BodyScanTiming.buildProgress(current: 0.42, fraction: 0.2), 0.42)
    XCTAssertLessThan(BodyScanTiming.buildProgress(current: 0,fraction: 2)!,1)
  }

  func testProgressAndTimingDoNotInventCompletionOrTime() {
    let photosOnly = BodyScanCameraStatus(mode: .capturing, shots: 500)
    XCTAssertFalse(photosOnly.awaitsNextStep)
    XCTAssertNil(photosOnly.action)
    XCTAssertEqual(photosOnly.progressTitle, "Pass 1 of 2 · Body circle in progress")
    var detail = BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 60)
    XCTAssertNil(detail.action)
    XCTAssertTrue(detail.progressDetail.contains("Finish the detail ring"))
    detail.completedPasses = 2
    detail.shots = 59
    detail.passComplete = true
    XCTAssertEqual(detail.action, .nextPass)
    XCTAssertEqual(detail.progressTitle, "More photo detail needed")
    detail.passComplete = false
    detail.shots = 60
    XCTAssertTrue(detail.awaitsNextStep)
    XCTAssertEqual(detail.action, .buildAvatar)
    XCTAssertEqual(detail.title, "Your capture is ready")
    for value: Double? in [nil, .nan, .infinity, -1, 0] {
      XCTAssertEqual(BodyScanTiming.remaining(value), "Estimating time remaining…")
    }
    XCTAssertEqual(BodyScanTiming.remaining(30), "Almost ready")
    XCTAssertFalse(BodyScanTiming.remaining(180).contains("Estimating"))
    let start = Date()
    XCTAssertEqual(BodyScanTiming.elapsed(since: start, now: start.addingTimeInterval(-1)), "Just started")
    XCTAssertTrue(BodyScanTiming.elapsed(since: start, now: start.addingTimeInterval(90)).contains("elapsed"))
  }

  @MainActor
  func testCameraChromeRendersAtNormalAndAccessibleSizes() throws {
    // Render the shipping camera chrome around a clearly synthetic, camera-free surface.
    // This checks layout; it does not pretend to capture a person in the simulator.
    for (name, size, typeSize, status) in [
      ("capture-body", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, shots: 23)),
      ("capture-standard", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43)),
      ("capture-accessible", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility2, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43)),
      ("capture-finding", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .framing, pendingAction: .findPerson)),
      ("capture-paused", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 30, passComplete: true, trackingNormal: false, issue: "Move a little closer.")),
      ("capture-paused-accessible", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility2, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 30, passComplete: true, trackingNormal: false, issue: "Move a little closer.")),
      ("capture-low-light", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43, trackingNormal: false, issue: "Find brighter, even light so we can see the person clearly.")),
      ("capture-out-of-view", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43, issue: "Bring the whole person back into view, with their head and feet visible.")),
      ("capture-tracking", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43, trackingNormal: false, issue: "Slowly move the iPhone so it can find the floor and settle its tracking.")),
      ("capture-limit", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 200, maximumShots: 200)),
      ("capture-limit-accessible", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility2, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 200, maximumShots: 200)),
      ("capture-ready", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 2, shots: 60, passComplete: true))
    ] {
      let root = BodyScanCameraView(status: status, startedAt: Date().addingTimeInterval(-75), close: {}, performAction: {}) {
        ZStack {
          Color(white: 0.18)
          Image(systemName: "figure.stand").font(.system(size: 140, weight: .ultraLight)).foregroundStyle(.white.opacity(0.35))
        }
      }
      .environment(\.dynamicTypeSize, typeSize)
      let host = UIHostingController(rootView: root)
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.setNeedsLayout()
      host.view.layoutIfNeeded()
      XCTAssertGreaterThan(host.view.bounds.height, 0)
      let image = UIGraphicsImageRenderer(size: size).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
      }
      let attachment = XCTAttachment(image: image)
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
      try XCTUnwrap(image.pngData()).write(to: url)
      print("SCAN_UX_RENDER \(url.path)")
      window.isHidden = true
    }
  }
}
