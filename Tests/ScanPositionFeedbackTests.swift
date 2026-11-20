import CoreHaptics
import CoreVideo
import XCTest
import Vision
@testable import FitCheck

final class ScanPositionFeedbackTests: XCTestCase {
  @MainActor
  func testDeviceWarningLoopStopsOnRecoveryStalenessAndDisabledSettings() async throws {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
      throw XCTSkip("This check requires real haptic hardware.")
    }
    let feedback = ScanHapticFeedback()
    defer { feedback.reset() }
    let now = ProcessInfo.processInfo.systemUptime
    let warning = ScanPositionFeedback(meters: 1, direction: .farther, severity: 0.8, observedAt: now)
    feedback.update(position: warning, active: true, enabled: true, foreground: true, now: now)
    XCTAssertTrue(feedback.playing, "The device must accept and start the continuous warning.")
    try await Task.sleep(for: .milliseconds(120))
    var safe = warning
    safe.direction = .hold
    feedback.update(position: safe, active: true, enabled: true, foreground: true, now: ProcessInfo.processInfo.systemUptime)
    XCTAssertFalse(feedback.playing)
    feedback.update(position: warning, active: true, enabled: true, foreground: true, now: ProcessInfo.processInfo.systemUptime)
    XCTAssertTrue(feedback.playing, "Recovery must not prevent a later warning.")
    feedback.update(position: warning, active: true, enabled: true, foreground: true, now: now + 1)
    XCTAssertFalse(feedback.playing, "Stale camera data must stop vibration.")
    for flags in [(false, true, true), (true, false, true), (true, true, false)] {
      let time = ProcessInfo.processInfo.systemUptime
      let fresh = ScanPositionFeedback(meters: 1, direction: .closer, severity: 0.8, observedAt: time)
      feedback.update(position: fresh, active: true, enabled: true, foreground: true, now: time)
      XCTAssertTrue(feedback.playing)
      feedback.update(position: fresh, active: flags.0, enabled: flags.1, foreground: flags.2, now: time)
      XCTAssertFalse(feedback.playing, "Pause, disabled haptics and backgrounding must stop vibration.")
    }
  }

  func testDepthGuidanceFiltersConfidenceMaskAndInvalidValues() throws {
    let depth = try buffer(format: kCVPixelFormatType_DepthFloat32, size: 32)
    let confidence = try buffer(format: kCVPixelFormatType_OneComponent8, size: 32)
    let mask = try buffer(format: kCVPixelFormatType_OneComponent8, size: 16)
    fill(depth, float: 1.25)
    fill(confidence, byte: 2)
    fill(mask, byte: 255)
    XCTAssertEqual(try XCTUnwrap(CaptureDepthSampler.meters(depth, confidence: confidence, mask: mask)), 1.25, accuracy: 0.001)

    fill(depth, left: 1, right: 2)
    XCTAssertEqual(CaptureDepthSampler.meters(depth), 2)
    XCTAssertEqual(CaptureDepthSampler.meters(depth, center: CGPoint(x: 0.25, y: 0.5)), 1)
    for center in [
      CGPoint(x: CGFloat.nan, y: 0.5), CGPoint(x: 0.5, y: CGFloat.nan),
      CGPoint(x: CGFloat.infinity, y: 0.5), CGPoint(x: 0.5, y: CGFloat.infinity),
      CGPoint(x: -0.01, y: 0.5), CGPoint(x: 0.5, y: -0.01),
      CGPoint(x: 1.01, y: 0.5), CGPoint(x: 0.5, y: 1.01)
    ] {
      XCTAssertNil(CaptureDepthSampler.meters(depth, center: center))
    }
    fill(depth, float: 1.25)
    let floatMask = try buffer(format: kCVPixelFormatType_OneComponent32Float, size: 16)
    fill(floatMask, float: 1)
    XCTAssertEqual(CaptureDepthSampler.meters(depth, mask: floatMask), 1.25)
    fill(floatMask, float: .nan)
    XCTAssertNil(CaptureDepthSampler.meters(depth, mask: floatMask))
    fill(confidence, byte: 0)
    XCTAssertNil(CaptureDepthSampler.meters(depth, confidence: confidence))
    fill(confidence, byte: 1)
    fill(mask, byte: 0)
    XCTAssertNil(CaptureDepthSampler.meters(depth, confidence: confidence, mask: mask))
    for value: Float in [.nan, .infinity, -1, 0, 5] {
      fill(depth, float: value)
      XCTAssertNil(CaptureDepthSampler.meters(depth))
    }
    XCTAssertNil(CaptureDepthSampler.meters(confidence))
  }


  func testBodyVisibilityNeverCallsMissingJointsCovered() {
    XCTAssertFalse(BodyCaptureEvidence.visible([.leftShoulder, .rightShoulder], in: [:]))
    XCTAssertFalse(BodyCaptureEvidence.visible([], in: [:]))
  }

  func testWholeBodyRequiresAHeadAndBothAnklesInsideTheImage() {
    var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
      .nose: CGPoint(x: 0.5, y: 0.9),
      .leftShoulder: CGPoint(x: 0.35, y: 0.75), .rightShoulder: CGPoint(x: 0.65, y: 0.75),
      .leftHip: CGPoint(x: 0.4, y: 0.5), .rightHip: CGPoint(x: 0.6, y: 0.5),
      .leftAnkle: CGPoint(x: 0.4, y: 0.1), .rightAnkle: CGPoint(x: 0.6, y: 0.1)
    ]
    XCTAssertTrue(BodyCaptureEvidence.fullyVisible(points))
    points[.leftAnkle] = nil
    XCTAssertFalse(BodyCaptureEvidence.fullyVisible(points))
    points[.leftAnkle] = CGPoint(x: 0.4, y: 0.005)
    XCTAssertFalse(BodyCaptureEvidence.fullyVisible(points))
    points[.leftAnkle] = CGPoint(x: 0.4, y: 0.1)
    points[.nose] = nil
    XCTAssertFalse(BodyCaptureEvidence.fullyVisible(points))
    points[.leftEar] = CGPoint(x: 0.5, y: 0.91)
    XCTAssertTrue(BodyCaptureEvidence.fullyVisible(points))
    points[.leftEar] = CGPoint(x: 0.5, y: 0.3)
    XCTAssertFalse(BodyCaptureEvidence.fullyVisible(points))
    points[.leftEar] = CGPoint(x: CGFloat.nan, y: 0.91)
    XCTAssertFalse(BodyCaptureEvidence.fullyVisible(points))
  }

  private func buffer(format: OSType, size: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, size, size, format, nil, &buffer), kCVReturnSuccess)
    return try XCTUnwrap(buffer)
  }
  private func fill(_ buffer: CVPixelBuffer, float: Float) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    for y in 0..<CVPixelBufferGetHeight(buffer) {
      let row = CVPixelBufferGetBaseAddress(buffer)!.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)
      for x in 0..<CVPixelBufferGetWidth(buffer) { row[x] = float }
    }
  }
  private func fill(_ buffer: CVPixelBuffer, byte: UInt8) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    memset(CVPixelBufferGetBaseAddress(buffer)!, Int32(byte), CVPixelBufferGetDataSize(buffer))
  }
  private func fill(_ buffer: CVPixelBuffer, left: Float, right: Float) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let width = CVPixelBufferGetWidth(buffer)
    for y in 0..<CVPixelBufferGetHeight(buffer) {
      let row = CVPixelBufferGetBaseAddress(buffer)!.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)
      for x in 0..<width { row[x] = x < width / 2 ? left : right }
    }
  }
}
