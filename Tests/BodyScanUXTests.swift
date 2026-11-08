import SwiftUI
import XCTest
@testable import FitCheck

final class BodyScanUXTests: XCTestCase {
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
    XCTAssertEqual(status.photoProgress, 0.5)
    status.completedPasses = 1
    status.passComplete = true
    XCTAssertEqual(status.action, .nextPass)
    XCTAssertEqual(status.actionTitle, "Continue to details")
    status.completedPasses = 2
    XCTAssertEqual(status.action, .nextPass)
    status.shots = 60
    XCTAssertEqual(status.action, .buildAvatar)
    status.issue = "Move more slowly."
    XCTAssertFalse(status.actionEnabled)
    XCTAssertEqual(status.instruction, "Move more slowly.")
    status.issue = nil
    status.trackingNormal = false
    XCTAssertFalse(status.actionEnabled)
    status = BodyScanCameraStatus(mode: .finishing)
    XCTAssertNil(status.action)
    XCTAssertEqual(status.step, .build)
  }

  func testProgressAndTimingDoNotInventCompletionOrTime() {
    XCTAssertEqual(BodyScanCameraStatus(mode: .capturing, shots: -1).photoProgress, 0)
    XCTAssertEqual(BodyScanCameraStatus(mode: .capturing, shots: 500).photoProgress, 1)
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
      ("capture-standard", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43)),
      ("capture-accessible", CGSize(width: 393, height: 852), DynamicTypeSize.accessibility2, BodyScanCameraStatus(mode: .capturing, completedPasses: 1, shots: 43)),
      ("capture-finding", CGSize(width: 393, height: 852), DynamicTypeSize.large, BodyScanCameraStatus(mode: .framing, pendingAction: .findPerson)),
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
