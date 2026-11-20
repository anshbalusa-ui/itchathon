import Foundation
import simd

struct BodyCaptureCalibrationObservation {
  var observedAt: TimeInterval
  var meters: Double
  var targetWorld: SIMD3<Float>
  var cameraTransform: simd_float4x4
  var referenceAxis: SIMD3<Float>
  var up: SIMD3<Float>
  var roll: Double
  var bounds: CGRect
  var fullBody: Bool
  var frontFacing: Bool
  var trackingNormal: Bool
  var stationary: Bool

  var isValid: Bool {
    observedAt.isFinite && (0.2...3).contains(meters) &&
      simd_length_squared(targetWorld).isFinite &&
      simd_length_squared(cameraTransform.columns.0).isFinite &&
      simd_length_squared(cameraTransform.columns.1).isFinite &&
      simd_length_squared(cameraTransform.columns.2).isFinite &&
      simd_length_squared(cameraTransform.columns.3).isFinite &&
      (0.99...1.01).contains(simd_length_squared(referenceAxis)) &&
      (0.99...1.01).contains(simd_length_squared(up)) && abs(roll) <= 8 * .pi / 180 &&
      bounds.minX >= 0.02 && bounds.minY >= 0.02 && bounds.maxX <= 0.98 && bounds.maxY <= 0.98 &&
      bounds.width >= 0.12 && bounds.height >= 0.45 &&
      abs(bounds.midX - 0.5) <= 0.10 && abs(bounds.midY - 0.5) <= 0.10 &&
      fullBody && frontFacing && trackingNormal && stationary
  }
}

struct BodyCaptureBaseline {
  let radius: Double
  let targetWorld: SIMD3<Float>
  let cameraTransform: simd_float4x4
  let previewHeight: Double
  let referenceAxis: SIMD3<Float>
  let up: SIMD3<Float>
}

struct BodyCaptureCalibration {
  private(set) var progress = 0.0
  private(set) var baseline: BodyCaptureBaseline?
  private var startTime: TimeInterval?
  private var previous: BodyCaptureCalibrationObservation?
  private var stableFrames = 0
  private var latest: BodyCaptureCalibrationObservation?
  private var axisSum = SIMD3<Float>.zero
  private var upSum = SIMD3<Float>.zero

  @discardableResult
  mutating func update(_ observation: BodyCaptureCalibrationObservation?, now: TimeInterval) -> Double {
    guard baseline == nil, now.isFinite, let observation, observation.isValid,
          observation.observedAt <= now, now - observation.observedAt <= 0.6 else {
      resetProgress()
      return progress
    }
    if let previous {
      let elapsed = observation.observedAt - previous.observedAt
      let movement = simd_distance(observation.targetWorld, previous.targetWorld)
      guard (0.12...0.55).contains(elapsed), movement <= 0.08,
            abs(observation.meters - previous.meters) <= 0.08,
            simd_length(observation.cameraTransform.columns.3 - previous.cameraTransform.columns.3) <= 0.05,
            simd_dot(observation.referenceAxis, previous.referenceAxis) >= cos(8 * .pi / 180),
            simd_dot(observation.up, previous.up) >= cos(8 * .pi / 180),
            abs(observation.roll - previous.roll) <= 0.06,
            abs(observation.bounds.midX - previous.bounds.midX) <= 0.05,
            abs(observation.bounds.midY - previous.bounds.midY) <= 0.05 else {
        resetProgress()
        return progress
      }
    } else {
      startTime = observation.observedAt
      stableFrames = 0
    }
    previous = observation
    latest = observation
    stableFrames += 1
    axisSum += observation.referenceAxis
    upSum += observation.up
    progress = min(1, max(0, (observation.observedAt - (startTime ?? observation.observedAt)) / 1.0))
    if stableFrames < 4 { progress = min(progress, 0.99) }
    return progress
  }

  func ready(now: TimeInterval) -> Bool {
    guard baseline == nil, progress >= 1, stableFrames >= 4, let latest else { return false }
    return now >= latest.observedAt && now - latest.observedAt <= 0.6
  }

  mutating func lockBaseline(now: TimeInterval) -> BodyCaptureBaseline? {
    guard ready(now: now), let latest,
          simd_length_squared(axisSum) > 1e-6, simd_length_squared(upSum) > 1e-6 else { return nil }
    let up = simd_normalize(upSum)
    let horizontal = axisSum - simd_dot(axisSum, up) * up
    guard simd_length_squared(horizontal) > 1e-6 else { return nil }
    let locked = BodyCaptureBaseline(radius: latest.meters, targetWorld: latest.targetWorld,
                                     cameraTransform: latest.cameraTransform, previewHeight: Double(latest.bounds.height),
                                     referenceAxis: simd_normalize(horizontal), up: up)
    baseline = locked
    return locked
  }

  mutating func reset() {
    baseline = nil
    resetProgress()
  }

  private mutating func resetProgress() {
    progress = 0
    startTime = nil
    previous = nil
    latest = nil
    stableFrames = 0
    axisSum = .zero
    upSum = .zero
  }
}
