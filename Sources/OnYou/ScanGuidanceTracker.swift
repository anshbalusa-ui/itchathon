import Foundation

struct ScanGuidanceSample: Sendable {
  var meters: Double?
  var targetMeters: Double?
  var bounds: CGRect?
  var tilt: CGPoint = .zero
  var roll: Double = 0
  var observedAt: TimeInterval
  var source = "Live LiDAR distance"
}

struct ScanGuidanceTracker {
  private struct AxisState {
    var side = 0
    var smoothedSeverity = 0.0
  }

  private struct Candidate {
    var direction: ScanPositionFeedback.Direction
    var severity: Double
  }

  private var distance = AxisState()
  private var framingX = AxisState()
  private var framingY = AxisState()
  private var tiltX = AxisState()
  private var tiltY = AxisState()
  private var roll = AxisState()
  private var clipping = AxisState()
  private var lastObservedAt: TimeInterval?
  private var lastUpdateAt: TimeInterval?

  mutating func update(_ sample: ScanGuidanceSample, now: TimeInterval) -> ScanPositionFeedback {
    guard now.isFinite, now >= 0, sample.observedAt.isFinite, sample.observedAt >= 0,
          now >= sample.observedAt, now - sample.observedAt <= 0.6,
          lastObservedAt.map({ sample.observedAt >= $0 }) ?? true else {
      reset()
      return ScanPositionFeedback()
    }

    if let lastObservedAt, sample.observedAt - lastObservedAt > 0.6 { reset() }
    let delta = min(0.6, max(0, now - (lastUpdateAt ?? now)))
    lastObservedAt = sample.observedAt
    lastUpdateAt = now
    var best: Candidate?
    var clippingWarning: Candidate?
    var oversized = false

    let validBounds = sample.bounds.map(Self.isValidBounds) ?? false
    if validBounds, let bounds = sample.bounds {
      let xError = bounds.midX - 0.5
      let yError = bounds.midY - 0.5
      let aimOffCenter = abs(xError) > 0.14 || abs(yError) > 0.14
      oversized = bounds.width > 0.90 || bounds.height > 0.90
      consider(axis: &framingX, value: xError, entry: 0.14, recovery: 0.10, scale: 0.45,
               positive: .right, negative: .left, delta: delta, best: &best)
      consider(axis: &framingY, value: yError, entry: 0.14, recovery: 0.10, scale: 0.45,
               positive: .down, negative: .up, delta: delta, best: &best)
      if aimOffCenter && !oversized {
        clipping = AxisState()
      } else {
        let nearestEdge = min(min(bounds.minX, bounds.minY), min(1 - bounds.maxX, 1 - bounds.maxY))
        consider(axis: &clipping, value: max(0, 0.075 - nearestEdge), entry: 0.039, recovery: 0, scale: 0.12,
                 positive: .farther, negative: .farther, delta: delta, best: &clippingWarning)
      }
    } else {
      framingX = AxisState()
      framingY = AxisState()
      clipping = AxisState()
    }

    let validRange = sample.meters.map { $0.isFinite && (0.2...3).contains($0) } == true &&
      sample.targetMeters.map { $0.isFinite && (0.2...3).contains($0) } == true
    if validRange, let meters = sample.meters, let target = sample.targetMeters {
      consider(axis: &distance, value: meters / target - 1, entry: 0.18, recovery: 0.12, scale: 0.60,
               positive: .closer, negative: .farther, delta: delta, best: &best)
    } else {
      distance = AxisState()
    }

    let tiltEntry = 12 * Double.pi / 180
    let tiltRecovery = 8 * Double.pi / 180
    let tiltScale = 30 * Double.pi / 180
    let validTiltX = sample.tilt.x.isFinite
    let validTiltY = sample.tilt.y.isFinite
    let validRoll = sample.roll.isFinite
    if validTiltX {
      consider(axis: &tiltX, value: Double(sample.tilt.x), entry: tiltEntry, recovery: tiltRecovery, scale: tiltScale,
               positive: .right, negative: .left, delta: delta, best: &best)
    } else {
      tiltX = AxisState()
    }
    if validTiltY {
      consider(axis: &tiltY, value: Double(sample.tilt.y), entry: tiltEntry, recovery: tiltRecovery, scale: tiltScale,
               positive: .down, negative: .up, delta: delta, best: &best)
    } else {
      tiltY = AxisState()
    }
    if validRoll {
      consider(axis: &roll, value: sample.roll, entry: tiltEntry, recovery: tiltRecovery, scale: tiltScale,
               positive: .level, negative: .level, delta: delta, best: &best)
    } else {
      roll = AxisState()
    }
    if let clippingWarning,
       oversized || (best.map { clippingWarning.severity > $0.severity } ?? true) {
      best = clippingWarning
    }

    let meters = validRange ? sample.meters : nil
    if let best {
      return ScanPositionFeedback(meters: meters, direction: best.direction, severity: best.severity,
                                  source: sample.source, observedAt: sample.observedAt)
    }
    guard validRange, validBounds, validTiltX, validTiltY, validRoll else {
      return ScanPositionFeedback(meters: meters, source: sample.source, observedAt: sample.observedAt)
    }
    return ScanPositionFeedback(meters: meters, direction: .hold, source: sample.source, observedAt: sample.observedAt)
  }

  mutating func reset() {
    distance = AxisState()
    framingX = AxisState()
    framingY = AxisState()
    tiltX = AxisState()
    tiltY = AxisState()
    roll = AxisState()
    clipping = AxisState()
    lastObservedAt = nil
    lastUpdateAt = nil
  }

  private static func isValidBounds(_ bounds: CGRect) -> Bool {
    bounds.minX.isFinite && bounds.minY.isFinite && bounds.maxX.isFinite && bounds.maxY.isFinite &&
      bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
  }

  private func consider(axis: inout AxisState, value: Double, entry: Double, recovery: Double, scale: Double,
                        positive: ScanPositionFeedback.Direction, negative: ScanPositionFeedback.Direction,
                        delta: TimeInterval, best: inout Candidate?) {
    if axis.side != 0 && value * Double(axis.side) <= recovery { axis.side = 0 }
    if axis.side == 0 && abs(value) > entry { axis.side = value > 0 ? 1 : -1 }
    guard axis.side != 0 else {
      axis.smoothedSeverity = 0
      return
    }

    let raw = min(1, max(0.12, (abs(value) - recovery) / scale))
    if axis.smoothedSeverity == 0 {
      axis.smoothedSeverity = raw
    } else {
      let smoothing = 1 - exp(-delta / 0.18)
      axis.smoothedSeverity += (raw - axis.smoothedSeverity) * smoothing
    }
    let candidate = Candidate(direction: axis.side > 0 ? positive : negative, severity: axis.smoothedSeverity)
    if let current = best {
      if candidate.severity > current.severity { best = candidate }
    } else {
      best = candidate
    }
  }
}
