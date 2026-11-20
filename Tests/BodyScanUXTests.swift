import SwiftUI
import SceneKit
import Observation
import simd
import XCTest
@testable import FitCheck

final class BodyScanUXTests: XCTestCase {
  func testFramingOutlineAndCaptureMarksHaveNoPolygonCorners() {
    let rect = CGRect(x: 0, y: 0, width: 393, height: 600)
    for outline in [true, false] {
      let path = BodyScanFramingGuide(showOutline: outline).path(in: rect).cgPath
      var curves = 0
      path.applyWithBlock { element in
        XCTAssertNotEqual(element.pointee.type, .addLineToPoint)
        if element.pointee.type == .addCurveToPoint { curves += 1 }
      }
      XCTAssertGreaterThanOrEqual(curves, 4)
      XCTAssertTrue(rect.contains(path.boundingBoxOfPath))
      XCTAssertEqual(path.boundingBoxOfPath.midX, rect.midX, accuracy: 0.01)
    }
  }

  func testSpatialDialUsesOnlyRecordedAnglesAndExpiresWithTracking() {
    var coverage = BodyCaptureCoverage()
    XCTAssertTrue(BodyCaptureGuideState.capturedBins(in: coverage).isEmpty)
    XCTAssertTrue(coverage.record(sampleID: 1, imageURL: URL(filePath: "/tmp/scan-guide-1.heic"), azimuth: 0, fullBody: true))
    XCTAssertTrue(coverage.record(sampleID: 2, imageURL: URL(filePath: "/tmp/scan-guide-2.heic"), azimuth: .pi, fullBody: false))
    let bins = BodyCaptureGuideState.capturedBins(in: coverage)
    XCTAssertEqual(bins, [0, 18])
    let state = BodyCaptureGuideState(placement: .init(transform: matrix_identity_float4x4, halfSize: SIMD2(0.5, 1)),
                                     capturedBins: bins, yaw: .pi / 2, neededAngle: .pi * 1.5, observedAt: 10)
    XCTAssertTrue(state.isFresh(now: 10.5))
    XCTAssertFalse(state.isFresh(now: 10.61))
    XCTAssertFalse(state.isFresh(now: 9.9))
    XCTAssertFalse(state.isFresh(now: .nan))
    XCTAssertEqual(state.capturedBins, bins, "Turning without a saved photo cannot fill the dial.")
    XCTAssertEqual(BodyCaptureGuideState.markerPosition(angle: 0).x, 0, accuracy: 0.001)
    XCTAssertGreaterThan(BodyCaptureGuideState.markerPosition(angle: .pi / 2).x, 1)
  }

  @MainActor
  func testSpatialGuideRetainsNodesAndCoverageAcrossUpdatesAndPause() throws {
    let guide = BodyCaptureSpatialGuide()
    var state = BodyCaptureGuideState(placement: .init(transform: matrix_identity_float4x4, halfSize: SIMD2(0.5, 1)),
                                     capturedBins: [0, 1], yaw: 0, neededAngle: .pi, observedAt: 10)
    guide.update(state, now: 10, reduceMotion: true)
    let halo = try XCTUnwrap(guide.root.childNodes.first)
    let nodes = halo.childNodes
    state.yaw = .pi / 2
    guide.update(state, now: 10.2, reduceMotion: true)
    XCTAssertEqual(guide.capturedBins, [0, 1])
    XCTAssertEqual(halo.childNodes.count, nodes.count)
    XCTAssertTrue(zip(nodes, halo.childNodes).allSatisfy { pair in pair.0 === pair.1 })
    XCTAssertTrue(halo.childNodes.allSatisfy { !$0.hasActions })
    guide.update(nil, now: 10.3, reduceMotion: true)
    XCTAssertTrue(guide.root.isHidden)
    guide.update(state, now: 10.4, reduceMotion: true)
    XCTAssertFalse(guide.root.isHidden)
    XCTAssertEqual(guide.capturedBins, [0, 1])
    guide.update(state, now: 10.7, reduceMotion: true)
    XCTAssertTrue(guide.root.isHidden)
  }

  @MainActor
  func testReviewZoomIsBoundedAndCameraAnimationsCanBeInterrupted() {
    let coordinator = BodySceneView.Coordinator()
    let view = SCNView()
    view.scene = coordinator.scene
    view.pointOfView = coordinator.camera
    coordinator.renderView = view
    coordinator.currentHeight = 1.75
    coordinator.reduceMotion = true
    coordinator.positionCamera(angle: 0, height: 1.75)
    let target = SIMD3<Float>(0, 1.75 * 0.51, 0.035)
    let initial = simd_distance(coordinator.camera.simdPosition, target)
    coordinator.zoom(view, factor: 0.8)
    XCTAssertLessThan(simd_distance(coordinator.camera.simdPosition, target), initial)
    for _ in 0..<25 { coordinator.zoom(view, factor: 0.8) }
    XCTAssertEqual(simd_distance(coordinator.camera.simdPosition, target), 1.75 * 0.65, accuracy: 0.001)
    for _ in 0..<25 { coordinator.zoom(view, factor: 1.25) }
    XCTAssertEqual(simd_distance(coordinator.camera.simdPosition, target), 1.75 * 3.5, accuracy: 0.001)
    XCTAssertFalse(coordinator.isCameraTransitioning)
    XCTAssertEqual(coordinator.makeAccessibilityActions(for: view).map(\.name),
                   ["Rotate left", "Rotate right", "Zoom in", "Zoom out", "Reset view"])
    coordinator.reduceMotion = false
    coordinator.inspect(view, angle: .pi, height: 1.75)
    XCTAssertTrue(coordinator.isCameraTransitioning)
    coordinator.interruptCameraTransition()
    XCTAssertFalse(coordinator.isCameraTransitioning)
  }

  @MainActor
  func testCameraInstanceAndViewportSurviveInstructionAndCaptureStateChanges() async throws {
    let state = ScanChromeTestState()
    var creations = 0
    var viewport = CGSize.zero
    let root = NavigationStack {
      ScanChromeTestView(state: state, created: { creations += 1 }, resized: { viewport = $0 })
    }
    let host = UIHostingController(rootView: root)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(80))
    host.view.layoutIfNeeded()
    let original = viewport
    for mode in [BodyScanCameraStatus.Mode.framing, .capturing, .finishing] {
      state.status.mode = mode
      state.status.instruction = "Keep the phone still while the person turns slowly."
      state.status.completedViews = [.front]
      try await Task.sleep(for: .milliseconds(80))
      host.view.layoutIfNeeded()
      XCTAssertEqual(viewport, original)
      XCTAssertEqual(creations, 1)
    }
    XCTAssertGreaterThan(original.height, 400)
  }

  @MainActor
  func testSpatialGuideRendersAroundSyntheticBody() async throws {
    let coordinator = BodySceneView.Coordinator()
    coordinator.update(.example)
    coordinator.camera.camera?.fieldOfView = 38
    let guide = BodyCaptureSpatialGuide()
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4(0, Float(BodyMeasurements.example.height / 200), 0.05, 1)
    let now = ProcessInfo.processInfo.systemUptime
    guide.update(BodyCaptureGuideState(placement: .init(transform: transform, halfSize: SIMD2(0.65, 0.98)),
                                       capturedBins: Set(0..<18), yaw: .pi * 0.8, neededAngle: .pi, observedAt: now),
                 now: now, reduceMotion: true)
    coordinator.scene.rootNode.addChildNode(guide.root)
    coordinator.scene.background.contents = UIColor(white: 0.08, alpha: 1)
    let renderer = SCNRenderer(device: nil, options: nil)
    renderer.scene = coordinator.scene
    renderer.pointOfView = coordinator.camera
    let rendered = renderer.snapshot(atTime: 0, with: CGSize(width: 393, height: 552), antialiasingMode: .multisampling4X)
    let cg = try XCTUnwrap(rendered.cgImage)
    var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cg.width, height: cg.height,
        bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    }
    let goldPixels = stride(from: 0, to: pixels.count, by: 4).filter {
      Int(pixels[$0]) > 210 && Int(pixels[$0 + 1]) > 170 &&
        Int(pixels[$0]) > Int(pixels[$0 + 2]) + 45 && Int(pixels[$0 + 1]) > Int(pixels[$0 + 2]) + 35
    }.count
    XCTAssertGreaterThan(goldPixels, 100, "The actual scene must render the confirmed coverage dial.")
    let root = NavigationStack {
      BodyScanCameraView(status: .init(mode: .capturing, completedViews: [.front, .firstSide],
                                       missingAngles: [.pi], instruction: "Show their back."), close: {}, performAction: {}) {
        Image(uiImage: rendered).resizable().scaledToFill()
          .overlay(alignment: .topLeading) {
            Text("Synthetic layout fixture").font(.caption).foregroundStyle(.white.opacity(0.7)).padding(12)
          }
      }
      .navigationTitle("Scan body").navigationBarTitleDisplayMode(.inline)
    }
    let host = UIHostingController(rootView: root)
    let size = CGSize(width: 393, height: 852)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    try await Task.sleep(for: .milliseconds(500))
    host.view.layoutIfNeeded()
    let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
    let attachment = XCTAttachment(image: image)
    attachment.name = "synthetic-spatial-scan-guide"
    attachment.lifetime = .keepAlways
    add(attachment)
    XCTAssertFalse(guide.root.isHidden)
  }

  @MainActor
  func testReviewRendersActualInputAndNativeCameraRespondsImmediately() async throws {
    let url = try XCTUnwrap(Bundle.main.url(forResource: "synthetic-avatar-a", withExtension: "usdz", subdirectory: "OnYouTryOnFixtures"))
    let digest = try AvatarScanStore.digest(url)
    let scene = try await PreparedAvatarScene.load(url: url)
    for typeSize in [DynamicTypeSize.large, .accessibility5] {
      var uses = 0
      var retakes = 0
      let root = NavigationStack {
        BodyScanReviewView(url: url, referenceHeightCM: scene.calibration.referenceHeightCM,
                           preparedScene: scene, retake: { retakes += 1 }, useScan: { uses += 1 })
          .navigationTitle("Review scan").navigationBarTitleDisplayMode(.inline)
      }
      .environment(\.dynamicTypeSize, typeSize)
      let host = UIHostingController(rootView: root)
      let size = CGSize(width: 393, height: 852)
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      window.rootViewController = host
      window.makeKeyAndVisible()
      try await Task.sleep(for: .milliseconds(400))
      host.view.layoutIfNeeded()
      func findScene(_ view: UIView) -> SCNView? {
        if let scene = view as? SCNView { return scene }
        return view.subviews.lazy.compactMap { findScene($0) }.first
      }
      let view = try XCTUnwrap(findScene(host.view))
      XCTAssertTrue(view.allowsCameraControl)
      XCTAssertEqual(view.defaultCameraController.inertiaEnabled, !UIAccessibility.isReduceMotionEnabled)
      let before = try XCTUnwrap(view.pointOfView).simdWorldPosition
      let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
      let end = CGPoint(x: center.x + 75, y: center.y)
      view.defaultCameraController.beginInteraction(center, withViewport: view.bounds.size)
      view.defaultCameraController.continueInteraction(end, withViewport: view.bounds.size, sensitivity: 1)
      view.defaultCameraController.endInteraction(end, withViewport: view.bounds.size, velocity: .zero)
      let turned = try XCTUnwrap(view.pointOfView).simdWorldPosition
      XCTAssertGreaterThan(simd_distance(before, turned), 0.01)
      view.defaultCameraController.dolly(by: 0.3, onScreenPoint: center, viewport: view.bounds.size)
      XCTAssertGreaterThan(simd_distance(turned, try XCTUnwrap(view.pointOfView).simdWorldPosition), 0.01)
      let image = UIGraphicsImageRenderer(size: size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
      let attachment = XCTAttachment(image: image)
      attachment.name = typeSize.isAccessibilitySize ? "scan-review-largest-text" : "scan-review"
      attachment.lifetime = .keepAlways
      add(attachment)
      XCTAssertEqual(uses, 0)
      XCTAssertEqual(retakes, 0)
      XCTAssertEqual(try AvatarScanStore.digest(url), digest)
      window.isHidden = true
    }
  }

  func testStartRequiresFreshCalibrationAndASeparateTap() {
    var status = BodyScanCameraStatus(mode: .framing)
    XCTAssertFalse(status.canStart(now: 10))
    status.calibrated = true
    XCTAssertFalse(status.canStart(now: 10))
    status.observedAt = 10
    XCTAssertTrue(status.canStart(now: 10.5))
    XCTAssertEqual(status.mode, .framing)
    XCTAssertFalse(status.canStart(now: 9.99))
    XCTAssertFalse(status.canStart(now: 10.61))
    XCTAssertFalse(status.canStart(now: .nan))
    status.pendingStart = true
    XCTAssertFalse(status.canStart(now: 10.5))
  }

  func testFinishingDoesNotEnableStartAndKeepsCompletedViews() {
    var status = BodyScanCameraStatus(mode: .capturing, calibrated: true, observedAt: 10,
                                      completedViews: Set(BodyCaptureView.allCases))
    XCTAssertFalse(status.canStart(now: 10))
    status.mode = .finishing
    XCTAssertFalse(status.canStart(now: 10))
    XCTAssertEqual(status.completedViews.count, 4)
    XCTAssertNil(status.neededView)
  }

  func testRecoveryHighlightsOnlyTheNextMissingViewInTurnOrder() {
    var status = BodyScanCameraStatus(mode: .framing, completedViews: [.front, .firstSide],
                                      missingAngles: [.pi, .pi / 2], direction: -1)
    XCTAssertEqual(status.neededView, .back)
    XCTAssertTrue(status.viewsAccessibilityValue.contains("Back needed."))
    status.missingAngles.removeFirst()
    XCTAssertEqual(status.neededView, .secondSide)
    XCTAssertEqual(status.completedViews, [.front, .firstSide])
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

  func testTimingDoesNotInventTime() {
    for value: Double? in [nil, .nan, .infinity, -1, 0] {
      XCTAssertEqual(BodyScanTiming.remaining(value), "Estimating time remaining…")
    }
    XCTAssertEqual(BodyScanTiming.remaining(30), "Almost ready")
    XCTAssertFalse(BodyScanTiming.remaining(180).contains("Estimating"))
  }

  @MainActor
  func testCameraChromeRendersAtNormalAndAccessibleSizesWithoutStartingCapture() async {
    let portrait = CGSize(width: 393, height: 852)
    let narrow = CGSize(width: 320, height: 568)
    let framing = BodyScanCameraStatus(mode: .framing, calibrationProgress: 0.4)
    var standardViewport: CGSize?
    let recovery = BodyScanCameraStatus(mode: .capturing, completedViews: [.front, .firstSide],
                                        missingAngles: [.pi], instruction: "Show their back.")
    for (name, size, typeSize, initialStatus) in [
      ("capture-framing", portrait, DynamicTypeSize.large, framing),
      ("capture-ready", portrait, .large, BodyScanCameraStatus(mode: .framing, calibrated: true, calibrationProgress: 1,
                                                               observedAt: ProcessInfo.processInfo.systemUptime,
                                                               instruction: "Ready. Ask them to keep this pose.")),
      ("capture-missing-back", portrait, .large, recovery),
      ("capture-accessible", portrait, .accessibility2, recovery),
      ("capture-narrow-accessible", narrow, .accessibility5, framing),
      ("capture-landscape", CGSize(width: 852, height: 393), .large, recovery),
      ("capture-finishing", portrait, .large, BodyScanCameraStatus(mode: .finishing, completedViews: Set(BodyCaptureView.allCases)))
    ] {
      var status = initialStatus
      if status.calibrated { status.observedAt = ProcessInfo.processInfo.systemUptime }
      var cameraActionCount = 0
      var viewport: CGSize = .zero
      // Render only the production chrome around a camera-free layout fixture.
      let root = NavigationStack {
        BodyScanCameraView(status: status, close: {}, performAction: { cameraActionCount += 1 }) {
          Color(white: 0.18)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { viewport = $0 }
        }
        .navigationTitle("Scan body")
        .navigationBarTitleDisplayMode(.inline)
      }
      .environment(\.dynamicTypeSize, typeSize)
      .environment(\.scenePhase, .active)
      let host = UIHostingController(rootView: root)
      let window = UIWindow(frame: CGRect(origin: .zero, size: size))
      if size == narrow { window.overrideUserInterfaceStyle = .light }
      window.rootViewController = host
      window.makeKeyAndVisible()
      host.view.frame = window.bounds
      host.view.setNeedsLayout()
      host.view.layoutIfNeeded()
      try? await Task.sleep(for: .milliseconds(400))
      host.view.layoutIfNeeded()
      let image = UIGraphicsImageRenderer(size: size).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
      }
      await Task.yield()
      XCTAssertGreaterThan(viewport.width, 0, name)
      XCTAssertGreaterThan(viewport.height, size.height * (typeSize.isAccessibilitySize ? 0.30 : 0.50), name)
      if size.width > size.height {
        XCTAssertLessThan(viewport.width, size.width, name)
      }
      if size == portrait && typeSize == .large {
        if let standardViewport { XCTAssertEqual(viewport, standardViewport, name) }
        else { standardViewport = viewport }
      }
      XCTAssertEqual(cameraActionCount, 0, name)

      let attachment = XCTAttachment(image: image)
      attachment.name = name
      attachment.lifetime = .keepAlways
      add(attachment)
      window.isHidden = true
    }
  }
}

@MainActor @Observable private final class ScanChromeTestState {
  var status = BodyScanCameraStatus(mode: .framing)
}

private struct ScanChromeTestView: View {
  var state: ScanChromeTestState
  var created: () -> Void
  var resized: (CGSize) -> Void

  var body: some View {
    BodyScanCameraView(status: state.status, close: {}, performAction: {}) {
      ScanCameraTestProbe(created: created)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { resized($0) }
    }
  }
}

private struct ScanCameraTestProbe: UIViewRepresentable {
  var created: () -> Void
  func makeUIView(context: Context) -> UIView { created(); return UIView() }
  func updateUIView(_ view: UIView, context: Context) {}
}
