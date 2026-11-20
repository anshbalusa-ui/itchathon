import simd
import XCTest
@testable import FitCheck

final class BodyCaptureTurnTests: XCTestCase {
  private let up = SIMD3<Float>(0, 1, 0)
  private let reference = SIMD3<Float>(1, 0, 0)

  func testTurningSubjectWithFixedPhoneCompletes() {
    var turn = BodyCaptureTurn()
    var coverage = BodyCaptureCoverage()
    var result = turn.feedback(coverage: coverage)
    for step in 0...72 {
      result = observe(&turn, &coverage, yaw: bodyYaw(step * 5), at: 1 + Double(step) * 0.3, fullBody: step < 3)
      if result.captureComplete { break }
    }
    XCTAssertTrue(result.captureComplete)
    XCTAssertEqual(result.completedViews, Set(BodyCaptureView.allCases))
    XCTAssertEqual(turn.direction, 1)
    XCTAssertTrue(coverage.hasCoverage())
    XCTAssertFalse(coverage.record(sampleID: 200, imageURL: imageURL(0), azimuth: radians(358), fullBody: true))

    for moves in [false, true] {
      var stationary = BodyCaptureTurn()
      var repeated = BodyCaptureCoverage()
      for step in 0..<120 {
        let translation = SIMD3<Float>(moves ? Float(step) * 0.01 : 0, 0, 0)
        let result = observe(&stationary, &repeated, yaw: bodyYaw(0, translation: translation),
                             at: 1 + Double(step) * 0.3, fullBody: true)
        XCTAssertFalse(result.captureComplete)
      }
      XCTAssertEqual(repeated.viewpoints.count, 1)
      XCTAssertNil(stationary.direction)
    }
  }

  func testMissingBackSectorKeepsAcceptedViews() {
    for direction in [1, -1] {
      var turn = BodyCaptureTurn()
      var coverage = BodyCaptureCoverage()
      var result = turn.feedback(coverage: coverage)
      for step in 0...72 {
        let angle = step * 5
        result = observe(&turn, &coverage, yaw: radians(direction * angle), at: 1 + Double(step) * 0.3,
                         usable: !(105...145).contains(angle), fullBody: step < 3)
      }
      XCTAssertFalse(result.captureComplete)
      XCTAssertTrue(turn.isRecovering)
      XCTAssertEqual(turn.direction, direction)
      let target = tryUnwrap(result.missingAngles.first)
      XCTAssertEqual(BodyCaptureCoverage.distance(target, radians(direction * 125)), 0, accuracy: 1e-6)
      XCTAssertTrue(result.missingAngles.allSatisfy {
        BodyCaptureCoverage.distance($0, radians(direction * 125)) <= radians(25)
      })
      let initialIDs = Set(coverage.viewpoints.map(\.sampleID))
      let initialViews = result.completedViews

      for step in 1...27 {
        let angle = step * 5
        result = observe(&turn, &coverage, yaw: radians(direction * angle), at: 1 + Double(step + 72) * 0.3,
                         usable: [110, 120, 135].contains(angle))
        if result.captureComplete { break }
      }
      XCTAssertTrue(result.captureComplete)
      XCTAssertTrue(initialViews.isSubset(of: result.completedViews))
      XCTAssertTrue(initialIDs.isSubset(of: Set(coverage.viewpoints.map(\.sampleID))))
      XCTAssertEqual(coverage.viewpoints.count - initialIDs.count, 2)
    }

    var coverage = BodyCaptureCoverage()
    for sampleID in 0..<60 {
      XCTAssertTrue(coverage.record(sampleID: sampleID, imageURL: imageURL(sampleID),
                                    azimuth: radians(sampleID * 6), fullBody: sampleID < 3))
    }
    var resumed = BodyCaptureTurn(direction: 1, recoveringAngles: [radians(120)])
    XCTAssertTrue(coverage.hasCoverage())
    XCTAssertFalse(resumed.feedback(coverage: coverage).captureComplete)
    let shifted = tryUnwrap(resumed.feedback(coverage: coverage).missingAngles.first)
    XCTAssertTrue(coverage.canRecord(azimuth: shifted))
    XCTAssertEqual(BodyCaptureCoverage.distance(shifted, radians(120)), radians(3), accuracy: 1e-6)
    resumed.resetObservation()
    for step in 0..<3 {
      let time = 1 + Double(step) * 0.3
      let feedback = resumed.update(yaw: shifted, observedAt: time, now: time, usable: true, coverage: coverage)
      XCTAssertFalse(feedback.captureComplete)
    }
    XCTAssertEqual(resumed.admissibleYaw, shifted)
    resumed.recorded(shifted + radians(1))
    XCTAssertFalse(resumed.feedback(coverage: coverage).captureComplete)
    XCTAssertTrue(coverage.record(sampleID: 60, imageURL: imageURL(60), azimuth: shifted, fullBody: false))
    resumed.recorded(shifted)
    XCTAssertTrue(resumed.feedback(coverage: coverage).captureComplete)
  }

  func testUncertainAndDiscontinuousPoseDoesNotFillCoverage() {
    XCTAssertNil(BodyCaptureTurn.yaw(shoulders: reference, hips: SIMD3(0, 0, 1), referenceAxis: reference, up: up))
    XCTAssertNil(BodyCaptureTurn.horizontalAxis(shoulders: up, hips: reference, up: up))
    XCTAssertNil(BodyCaptureTurn.horizontalAxis(shoulders: SIMD3(.nan, 0, 0), hips: reference, up: up))

    var turn = BodyCaptureTurn()
    var coverage = BodyCaptureCoverage()
    _ = observe(&turn, &coverage, yaw: 0, at: 1, fullBody: true)
    _ = observe(&turn, &coverage, yaw: radians(5), at: 1.3, usable: false)
    XCTAssertEqual(tryUnwrap(turn.yawRate), radians(5) / 0.3, accuracy: 1e-6)
    XCTAssertNil(turn.admissibleYaw)
    _ = observe(&turn, &coverage, yaw: radians(10), at: 1.6)

    for (angle, observed, now) in [(190, 1.9, 1.9), (15, 2.0, 2.7), (15, 2.4, 2.3), (10, 1.6, 2.0)] {
      _ = turn.update(yaw: radians(angle), observedAt: observed, now: now, usable: true, coverage: coverage)
      XCTAssertNil(turn.admissibleYaw)
      XCTAssertNil(turn.yawRate)
    }
    _ = turn.update(yaw: nil, observedAt: 2.5, now: 2.5, usable: true, coverage: coverage)
    XCTAssertNil(turn.admissibleYaw)
    for (step, angle) in [60, 62, 64].enumerated() {
      let time = 3 + Double(step) * 0.3
      let result = observe(&turn, &coverage, yaw: radians(angle), at: time)
      XCTAssertFalse(result.captureComplete)
      XCTAssertEqual(coverage.viewpoints.count, step < 2 ? 2 : 3)
    }
    XCTAssertEqual(tryUnwrap(coverage.viewpoints.last?.azimuth), radians(64), accuracy: 1e-6)
    XCTAssertNil(turn.admissibleYaw)

    _ = turn.update(yaw: radians(72), observedAt: 3.7, now: 3.7, usable: true, coverage: coverage)
    XCTAssertNil(turn.yawRate)
    XCTAssertNil(turn.admissibleYaw)
    XCTAssertFalse(coverage.hasCoverage())
    XCTAssertFalse(coverage.viewpoints.contains { BodyCaptureCoverage.distance($0.azimuth, radians(30)) < radians(5) })
  }

  func testAlignedPosesMustSurroundSubject() {
    var coverage = BodyCaptureCoverage()
    var poses: [Int: BodyCaptureReconstructedPose] = [:]
    for sampleID in 0..<72 {
      XCTAssertTrue(coverage.record(sampleID: sampleID, imageURL: imageURL(sampleID),
                                    azimuth: radians(sampleID * 5), fullBody: sampleID < 4))
      // Native coordinates are rotated and mirrored relative to the stored subject labels.
      poses[sampleID] = nativePose(degrees: 33 - (sampleID == 1 ? 1 : sampleID * 5))
    }
    XCTAssertTrue(coverage.hasCoverage())
    if case .complete = coverage.alignedCoverage(poses: poses, rejectedIDs: []) {} else {
      XCTFail("Nearby native angles should not discard distinct source photos.")
    }
    if case .complete = coverage.alignedCoverage(poses: poses, rejectedIDs: [0]) {} else {
      XCTFail("The fitted offset should recover frontal zero if the first front sample was rejected.")
    }

    let rejected = Set(32...39)
    let retainedIDs = Set(poses.keys).subtracting(rejected)
    let retained = coverage.retaining(sampleIDs: retainedIDs)
    guard case .missingAngles(let targets) = coverage.alignedCoverage(poses: poses, rejectedIDs: rejected) else {
      return XCTFail("An aligned back gap should ask for new back views.")
    }
    XCTAssertFalse(targets.isEmpty)
    XCTAssertTrue(targets.allSatisfy { BodyCaptureCoverage.distance($0, .pi) <= radians(25) })
    XCTAssertTrue(targets.allSatisfy { retained.canRecord(azimuth: $0) })
    XCTAssertEqual(Set(retained.viewpoints.map(\.sampleID)), retainedIDs)

    let sparse = poses.filter { $0.key.isMultiple(of: 2) || $0.key == 3 }
    guard case .missingAngles(let extra) = coverage.alignedCoverage(poses: sparse, rejectedIDs: []) else {
      return XCTFail("Coherent native views below the photo floor should remain recoverable.")
    }
    let sparseCoverage = coverage.retaining(sampleIDs: Set(sparse.keys))
    XCTAssertFalse(extra.isEmpty)
    XCTAssertTrue(extra.allSatisfy { sparseCoverage.canRecord(azimuth: $0) })

    let frontOnly = poses.filter { $0.key < 10 || $0.key > 62 }
    let parallel = poses.mapValues { BodyCaptureReconstructedPose(translation: $0.translation,
                                                                 rotation: simd_quatf(angle: 0, axis: up)) }
    var unknown = poses
    unknown[999] = nativePose(degrees: 0)
    var invalid = poses
    invalid[0]?.translation.x = .nan
    for candidate in [frontOnly, parallel, unknown, invalid] {
      if case .invalid = coverage.alignedCoverage(poses: candidate, rejectedIDs: []) {} else {
        XCTFail("Invalid or front-only poses must not establish a turn.")
      }
    }
  }

  private func bodyYaw(_ degrees: Int, translation: SIMD3<Float> = .zero) -> Double? {
    let root = SIMD3<Float>(0, 0, -2) - translation
    let shoulder = root + SIMD3<Float>(0, 0.5, 0)
    let half = simd_quatf(angle: Float(radians(degrees)), axis: up).act(reference) * 0.25
    return BodyCaptureTurn.yaw(leftShoulder: shoulder - half, rightShoulder: shoulder + half,
                               leftHip: root - half, rightHip: root + half, referenceAxis: reference, up: up)
  }

  private func nativePose(degrees: Int) -> BodyCaptureReconstructedPose {
    let rotation = simd_quatf(angle: Float(radians(degrees)), axis: up)
    let target = SIMD3<Float>(0.1, 0.8, -0.3)
    return BodyCaptureReconstructedPose(translation: target + rotation.act(SIMD3(0, 0, 2)), rotation: rotation)
  }

  private func observe(_ turn: inout BodyCaptureTurn, _ coverage: inout BodyCaptureCoverage,
                       yaw: Double?, at time: Double, usable: Bool = true, fullBody: Bool = false) -> BodyCaptureTurnFeedback {
    _ = turn.update(yaw: yaw, observedAt: time, now: time, usable: usable, coverage: coverage)
    if let angle = turn.admissibleYaw {
      let sampleID = coverage.viewpoints.count
      XCTAssertTrue(coverage.record(sampleID: sampleID, imageURL: imageURL(sampleID), azimuth: angle, fullBody: fullBody))
      turn.recorded(angle)
    }
    return turn.feedback(coverage: coverage)
  }

  private func imageURL(_ sampleID: Int) -> URL {
    URL(fileURLWithPath: "/body-turn-fixture/\(sampleID).jpg")
  }

  private func radians(_ degrees: Int) -> Double {
    Double(degrees) * .pi / 180
  }

  private func tryUnwrap(_ value: Double?, file: StaticString = #filePath, line: UInt = #line) -> Double {
    XCTAssertNotNil(value, file: file, line: line)
    return value ?? .nan
  }
}
