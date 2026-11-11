import CoreVideo
import XCTest
import Vision
@testable import FitCheck

final class ScanPositionFeedbackTests: XCTestCase {
  func testDistanceGradientAndMissingDepthStayHonest() {
    let perfect = ScanPositionFeedback.shirt(meters: 1, target: 1, bounds: nil, level: 1)
    XCTAssertEqual(perfect.quality, 1)
    XCTAssertEqual(perfect.direction, .hold)
    XCTAssertEqual(perfect.intensity, 0)
    let close = ScanPositionFeedback.shirt(meters: 0.7, target: 1, bounds: nil, level: 1)
    let closer = ScanPositionFeedback.shirt(meters: 0.4, target: 1, bounds: nil, level: 1)
    XCTAssertEqual(close.direction, .farther)
    XCTAssertGreaterThan(close.quality, closer.quality)
    XCTAssertGreaterThan(closer.intensity, close.intensity)
    let far = ScanPositionFeedback.shirt(meters: 1.4, target: 1, bounds: nil, level: 1)
    let farther = ScanPositionFeedback.shirt(meters: 1.8, target: 1, bounds: nil, level: 1)
    XCTAssertEqual(far.direction, .closer)
    XCTAssertGreaterThan(far.quality, farther.quality)
    for meters: Double? in [nil, .nan, .infinity, -1, 0] {
      let missing = ScanPositionFeedback.shirt(meters: meters, target: 1, bounds: nil, level: 1)
      XCTAssertEqual(missing.direction, .searching)
      XCTAssertEqual(missing.distanceText, "—")
      XCTAssertEqual(missing.intensity, 0)
    }
  }

  func testPositionGuidesPhoneTowardShirtAndToleratesModerateTilt() {
    for (bounds, direction) in [
      (CGRect(x: 0.01, y: 0.25, width: 0.4, height: 0.5), ScanPositionFeedback.Direction.left),
      (CGRect(x: 0.59, y: 0.25, width: 0.4, height: 0.5), .right),
      (CGRect(x: 0.25, y: 0.01, width: 0.5, height: 0.5), .up),
      (CGRect(x: 0.25, y: 0.49, width: 0.5, height: 0.5), .down),
      (CGRect(x: 0, y: 0, width: 0.95, height: 0.95), .farther)
    ] {
      XCTAssertEqual(ScanPositionFeedback.shirt(meters: 1, target: 1, bounds: bounds, level: 0.93).direction, direction)
    }
    XCTAssertEqual(ScanPositionFeedback.shirt(meters: 1, target: 1, bounds: nil, level: 0.91).direction, .hold)
    XCTAssertEqual(ScanPositionFeedback.shirt(meters: 1, target: 1, bounds: nil, level: 0.89).direction, .level)
  }

  func testDepthGuidanceFiltersConfidenceMaskAndInvalidValues() throws {
    let depth = try buffer(format: kCVPixelFormatType_DepthFloat32, size: 32)
    let confidence = try buffer(format: kCVPixelFormatType_OneComponent8, size: 32)
    let mask = try buffer(format: kCVPixelFormatType_OneComponent8, size: 16)
    fill(depth, float: 1.25)
    fill(confidence, byte: 2)
    fill(mask, byte: 255)
    XCTAssertEqual(try XCTUnwrap(CaptureDepthSampler.meters(depth, confidence: confidence, mask: mask)), 1.25, accuracy: 0.001)
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

  func testBodyReadingsExpireAndLiveNearFarFeedbackTakesPrecedence() {
    let now = Date()
    let current = ScanPositionFeedback.body(meters: 1.4, capturedAt: now, now: now, tooClose: false, tooFar: false, framed: true)
    XCTAssertEqual(current.meters, 1.4)
    XCTAssertTrue(current.source.contains("Not live"))
    let stale = ScanPositionFeedback.body(meters: 1.4, capturedAt: now.addingTimeInterval(-6), now: now, tooClose: true, tooFar: false, framed: true)
    XCTAssertNil(stale.meters)
    XCTAssertEqual(stale.direction, .farther)
    XCTAssertEqual(stale.intensity, 1)
    XCTAssertEqual(ScanPositionFeedback.body(meters: nil, capturedAt: nil, now: now, tooClose: false, tooFar: true, framed: false).direction, .closer)
    XCTAssertEqual(ScanPositionFeedback.body(meters: nil, capturedAt: nil, now: now, tooClose: false, tooFar: false, framed: false).direction, .searching)
    XCTAssertNil(ScanPositionFeedback.body(meters: 1.4, capturedAt: now.addingTimeInterval(1), now: now, tooClose: false, tooFar: false, framed: true).meters)
  }

  func testBodyVisibilityNeverCallsMissingJointsCovered() {
    XCTAssertFalse(BodyCaptureEvidence.visible([.leftShoulder, .rightShoulder], in: [:]))
    XCTAssertFalse(BodyCaptureEvidence.visible([], in: [:]))
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
}
