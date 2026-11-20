import XCTest
@testable import FitCheck

final class ScanGuidanceTrackerTests: XCTestCase {
  func testLockedDistanceRatioGuidesBothDirectionsAndGradesMagnitude() {
    var nearTracker = ScanGuidanceTracker()
    let near = nearTracker.update(sample(meters: 0.81, at: 1), now: 1)
    let nearer = nearTracker.update(sample(meters: 0.5, at: 1.1), now: 1.1)
    XCTAssertEqual(near.direction, .farther)
    XCTAssertEqual(nearer.direction, .farther)
    XCTAssertGreaterThan(nearer.severity, near.severity)

    var farTracker = ScanGuidanceTracker()
    let far = farTracker.update(sample(meters: 1.19, at: 2), now: 2)
    let farther = farTracker.update(sample(meters: 1.8, at: 2.1), now: 2.1)
    XCTAssertEqual(far.direction, .closer)
    XCTAssertEqual(farther.direction, .closer)
    XCTAssertGreaterThan(farther.severity, far.severity)

    for step in 0..<5 {
      let stillFar = farTracker.update(sample(meters: 1.2, at: 2.2 + Double(step) * 0.1), now: 2.2 + Double(step) * 0.1)
      XCTAssertEqual(stillFar.direction, .closer)
    }
  }

  func testDistanceHysteresisRejectsThresholdChatter() {
    var tracker = ScanGuidanceTracker()
    XCTAssertEqual(tracker.update(sample(meters: 0.81, at: 1), now: 1).direction, .farther)
    XCTAssertEqual(tracker.update(sample(meters: 0.83, at: 1.1), now: 1.1).direction, .farther)
    let recovered = tracker.update(sample(meters: 0.89, at: 1.2), now: 1.2)
    XCTAssertEqual(recovered.direction, .hold)
    XCTAssertEqual(recovered.intensity, 0)
    XCTAssertEqual(tracker.update(sample(meters: 0.83, at: 1.3), now: 1.3).direction, .hold)
    XCTAssertEqual(tracker.update(sample(meters: 0.81, at: 1.4), now: 1.4).direction, .farther)
  }

  func testSeveritySmoothsWithErrorAndFallsDuringRecovery() {
    var tracker = ScanGuidanceTracker()
    let moderate = tracker.update(sample(meters: 0.8, at: 4), now: 4)
    let severe = tracker.update(sample(meters: 0.6, at: 4.1), now: 4.1)
    let recovering = tracker.update(sample(meters: 0.8, at: 4.2), now: 4.2)
    XCTAssertGreaterThan(severe.severity, moderate.severity)
    XCTAssertLessThan(recovering.severity, severe.severity)
    XCTAssertGreaterThan(recovering.intensity, 0)
    let safe = tracker.update(sample(meters: 0.89, at: 4.3), now: 4.3)
    XCTAssertEqual(safe.direction, .hold)
    XCTAssertEqual(safe.severity, 0)
    XCTAssertEqual(safe.intensity, 0)
  }

  func testFramingTiltAndRollAxesRemainIndependent() {
    let centered = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    for (bounds, expected) in [
      (CGRect(x: 0.1, y: 0.4, width: 0.2, height: 0.2), ScanPositionFeedback.Direction.left),
      (CGRect(x: 0.7, y: 0.4, width: 0.2, height: 0.2), .right),
      (CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.2), .up),
      (CGRect(x: 0.4, y: 0.7, width: 0.2, height: 0.2), .down)
    ] {
      var tracker = ScanGuidanceTracker()
      XCTAssertEqual(tracker.update(sample(bounds: bounds, at: 1), now: 1).direction, expected)
    }

    for (tilt, expected) in [
      (CGPoint(x: 0.3, y: 0), ScanPositionFeedback.Direction.right),
      (CGPoint(x: -0.3, y: 0), .left),
      (CGPoint(x: 0, y: 0.3), .down),
      (CGPoint(x: 0, y: -0.3), .up)
    ] {
      var tracker = ScanGuidanceTracker()
      XCTAssertEqual(tracker.update(sample(bounds: centered, tilt: tilt, at: 1), now: 1).direction, expected)
    }

    var rollTracker = ScanGuidanceTracker()
    XCTAssertEqual(rollTracker.update(sample(bounds: centered, roll: 0.3, at: 1), now: 1).direction, .level)
  }

  func testFreshAimGuidesWithoutDepthAndClippingDoesNotMaskAim() {
    var offscreenTracker = ScanGuidanceTracker()
    let smallOffLeft = CGRect(x: -0.02, y: 0.4, width: 0.12, height: 0.2)
    let left = offscreenTracker.update(sample(meters: nil, target: nil, bounds: smallOffLeft, at: 1), now: 1)
    XCTAssertNil(left.meters)
    XCTAssertEqual(left.direction, .left)
    XCTAssertGreaterThan(left.intensity, 0)

    var tiltTracker = ScanGuidanceTracker()
    let tilt = tiltTracker.update(sample(meters: nil, target: nil, tilt: CGPoint(x: 0.3, y: 0), at: 1), now: 1)
    XCTAssertEqual(tilt.direction, .right)
    XCTAssertNil(tilt.meters)

    var clippingTracker = ScanGuidanceTracker()
    let oversizedCentered = CGRect(x: 0.02, y: 0.3, width: 0.96, height: 0.4)
    let clipped = clippingTracker.update(sample(meters: nil, target: nil, bounds: oversizedCentered, at: 1), now: 1)
    XCTAssertNil(clipped.meters)
    XCTAssertEqual(clipped.direction, .farther)
    XCTAssertGreaterThan(clipped.severity, 0)
    let oversizedOffCenter = CGRect(x: 0.18, y: 0.3, width: 0.96, height: 0.4)
    var offCenterClippingTracker = ScanGuidanceTracker()
    let back = offCenterClippingTracker.update(sample(meters: nil, target: nil, bounds: oversizedOffCenter, at: 1.1), now: 1.1)
    XCTAssertEqual(back.direction, .farther)
  }

  func testMissingInvalidStaleAndOutOfOrderReadingsNeverBecomeGood() {
    for invalid in [
      sample(meters: nil, at: 1),
      sample(target: nil, at: 1),
      sample(meters: .nan, at: 1),
      sample(target: .infinity, at: 1),
      sample(tilt: CGPoint(x: CGFloat.nan, y: 0), at: 1),
      sample(bounds: CGRect(x: CGFloat.infinity, y: 0.4, width: 0.2, height: 0.2), at: 1),
      sample(meters: 0.1, at: 1),
      sample(target: 0, at: 1),
      sample(tilt: CGPoint(x: 0, y: CGFloat.nan), at: 1),
      sample(roll: .nan, at: 1),
      sample(bounds: CGRect(x: 0.4, y: CGFloat.nan, width: 0.2, height: 0.2), at: 1),
      sample(at: .nan)
    ] {
      var tracker = ScanGuidanceTracker()
      let result = tracker.update(invalid, now: 1)
      XCTAssertNotEqual(result.direction, .hold)
      XCTAssertEqual(result.direction, .searching)
      XCTAssertEqual(result.intensity, 0)
    }
    var invalidTimestampTracker = ScanGuidanceTracker()
    let invalidTimestamp = invalidTimestampTracker.update(sample(at: 1), now: .infinity)
    XCTAssertEqual(invalidTimestamp.direction, .searching)

    var staleTracker = ScanGuidanceTracker()
    let stale = staleTracker.update(sample(at: 1), now: 1.61)
    XCTAssertEqual(stale.direction, .searching)
    XCTAssertNil(stale.observedAt)
    let future = staleTracker.update(sample(at: 2), now: 1.9)
    XCTAssertEqual(future.direction, .searching)

    var orderedTracker = ScanGuidanceTracker()
    XCTAssertEqual(orderedTracker.update(sample(meters: 0.6, at: 3), now: 3).direction, .farther)
    let outOfOrder = orderedTracker.update(sample(at: 2.95), now: 3)
    XCTAssertEqual(outOfOrder.direction, .searching)
    XCTAssertNil(outOfOrder.observedAt)
    XCTAssertEqual(orderedTracker.update(sample(at: 3.1), now: 3.1).direction, .hold)
  }

  private func sample(meters: Double? = 1, target: Double? = 1,
                      bounds: CGRect? = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                      tilt: CGPoint = .zero, roll: Double = 0, at time: TimeInterval) -> ScanGuidanceSample {
    ScanGuidanceSample(meters: meters, targetMeters: target, bounds: bounds, tilt: tilt, roll: roll, observedAt: time)
  }
}
