import Foundation
import simd

enum BodyCaptureView: Int, CaseIterable, Sendable {
  case front, firstSide, back, secondSide

  var title: String {
    switch self {
    case .front: "Front"
    case .firstSide: "Side"
    case .back: "Back"
    case .secondSide: "Other side"
    }
  }

  static func nearest(to yaw: Double, direction: Int) -> Self {
    guard yaw.isFinite else { return .front }
    let angle = BodyCaptureCoverage.normalized(direction < 0 ? -yaw : yaw)
    return allCases[Int((angle / (.pi / 2)).rounded()) % allCases.count]
  }

  fileprivate func center(direction: Int) -> Double {
    Double(rawValue) * (.pi / 2) * (direction < 0 ? -1 : 1)
  }

  fileprivate var request: String {
    switch self {
    case .front: "Face the camera."
    case .back: "Show your back to the camera."
    case .firstSide, .secondSide: "Turn slowly to show your side."
    }
  }
}

struct BodyCaptureTurnFeedback: Sendable {
  var completedViews: Set<BodyCaptureView>
  var missingAngles: [Double]
  var instruction: String
  var captureComplete: Bool
}

struct BodyCaptureTurn {
  private static let maximumAge = 0.6
  private static let maximumRate = 25 * Double.pi / 180
  private static let maximumJump = 15 * Double.pi / 180
  private static let reacquisitionWindow = 5 * Double.pi / 180
  private static let frontReturn = 20 * Double.pi / 180
  private static let targetWindow = 8 * Double.pi / 180
  private static let tolerance = BodyCaptureCoverage.angleTolerance

  private struct Pose {
    let yaw: Double
    let time: TimeInterval
  }

  private struct Reacquisition {
    let anchor: Double
    var last: Pose
    var minimum = 0.0
    var maximum = 0.0
    var count = 1
  }

  private(set) var direction: Int?
  private(set) var admissibleYaw: Double?
  private(set) var yawRate: Double?
  private(set) var isRecovering: Bool
  private(set) var turningTooFast = false
  private var requestedAngles: [Double] = []
  private var admittedRequest = false
  private var lastTimestamp: TimeInterval?
  private var lastPose: Pose?
  private var poseUsable = false
  private var needsReacquisition = false
  private var candidate: Reacquisition?
  private var departure = 0.0
  private var sidesObserved = 0
  private var returnedToFront = false

  init(direction: Int? = nil, recoveringAngles: [Double] = []) {
    self.direction = direction == -1 || direction == 1 ? direction : nil
    isRecovering = !recoveringAngles.isEmpty
    for angle in recoveringAngles where angle.isFinite {
      let angle = BodyCaptureCoverage.normalized(angle)
      if requestedAngles.allSatisfy({ BodyCaptureCoverage.distance(angle, $0) >= BodyCaptureCoverage.duplicateAngle - Self.tolerance }) {
        requestedAngles.append(angle)
      }
    }
  }

  static func horizontalAxis(shoulders: SIMD3<Float>, hips: SIMD3<Float>, up: SIMD3<Float>) -> SIMD3<Float>? {
    guard let up = unit(up), let shoulder = unit(shoulders - up * simd_dot(shoulders, up)),
          let hip = unit(hips - up * simd_dot(hips, up)),
          simd_dot(shoulder, hip) >= cos(Float(20 * .pi / 180 + tolerance)) else { return nil }
    return unit(shoulder + hip)
  }

  static func yaw(leftShoulder: SIMD3<Float>, rightShoulder: SIMD3<Float>,
                  leftHip: SIMD3<Float>, rightHip: SIMD3<Float>,
                  referenceAxis: SIMD3<Float>, up: SIMD3<Float>) -> Double? {
    yaw(shoulders: rightShoulder - leftShoulder, hips: rightHip - leftHip, referenceAxis: referenceAxis, up: up)
  }

  static func yaw(shoulders: SIMD3<Float>, hips: SIMD3<Float>,
                  referenceAxis: SIMD3<Float>, up: SIMD3<Float>) -> Double? {
    guard let up = unit(up), let axis = horizontalAxis(shoulders: shoulders, hips: hips, up: up),
          let reference = unit(referenceAxis - up * simd_dot(referenceAxis, up)) else { return nil }
    return atan2(Double(simd_dot(up, simd_cross(reference, axis))), Double(simd_dot(reference, axis)))
  }

  private static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
    let length = simd_length(vector)
    return length.isFinite && length > 1e-6 ? vector / length : nil
  }

  mutating func resetObservation() {
    lastTimestamp = nil
    losePose()
    admissibleYaw = nil
    admittedRequest = false
    yawRate = nil
    turningTooFast = false
  }

  mutating func update(yaw: Double?, observedAt: TimeInterval, now: TimeInterval,
                       usable: Bool, coverage: BodyCaptureCoverage) -> BodyCaptureTurnFeedback {
    admissibleYaw = nil
    admittedRequest = false
    yawRate = nil
    turningTooFast = false
    observe(yaw: yaw, observedAt: observedAt, now: now)
    poseUsable = usable && lastPose != nil
    // Finish can be near front, but leave time to capture the wrap before asking for a missing angle.
    if returnedToFront, !isRecovering, let pose = lastPose,
       BodyCaptureCoverage.distance(pose.yaw, 0) <= Self.reacquisitionWindow + Self.tolerance,
       !coverage.hasCoverage() {
      isRecovering = true
    }

    let distinctYaw = distinctYaw(coverage: coverage)
    let result = feedback(coverage: coverage, distinctYaw: distinctYaw)
    if let distinctYaw, !result.captureComplete {
      if !isRecovering {
        admissibleYaw = distinctYaw
      } else if let target = result.missingAngles.first,
                BodyCaptureCoverage.distance(distinctYaw, target) <= Self.targetWindow + Self.tolerance {
        admissibleYaw = distinctYaw
        admittedRequest = !requestedAngles.isEmpty
      }
    }
    return result
  }

  mutating func recorded(_ yaw: Double) {
    guard yaw.isFinite, let admissibleYaw,
          BodyCaptureCoverage.distance(yaw, admissibleYaw) <= Self.tolerance else { return }
    if admittedRequest { requestedAngles.removeFirst() }
    self.admissibleYaw = nil
    admittedRequest = false
  }

  func feedback(coverage: BodyCaptureCoverage) -> BodyCaptureTurnFeedback {
    feedback(coverage: coverage, distinctYaw: distinctYaw(coverage: coverage))
  }

  private func distinctYaw(coverage: BodyCaptureCoverage) -> Double? {
    guard poseUsable, let yaw = lastPose?.yaw, coverage.canRecord(azimuth: yaw) else { return nil }
    return yaw
  }

  private func feedback(coverage: BodyCaptureCoverage, distinctYaw: Double?) -> BodyCaptureTurnFeedback {
    let views = completedViews(coverage: coverage)
    let isFront = lastPose.map { BodyCaptureCoverage.distance($0.yaw, 0) <= Self.frontReturn + Self.tolerance } ?? false
    let atFinish = isRecovering || (returnedToFront && isFront)
    if atFinish, requestedAngles.isEmpty, coverage.hasCoverage() {
      return BodyCaptureTurnFeedback(completedViews: views, missingAngles: [], instruction: "Capture complete.", captureComplete: true)
    }
    let targets = isRecovering ? recoveryTargets(coverage: coverage) : []
    let instruction: String
    if turningTooFast {
      instruction = "Turn more slowly. Hold your pose."
    } else if let target = targets.first {
      let direction = direction ?? 1
      let view = BodyCaptureView.nearest(to: target, direction: direction)
      if let current = lastPose?.yaw {
        let delta = BodyCaptureCoverage.signed(target - current) * Double(direction)
        if abs(delta) <= Self.targetWindow + Self.tolerance, distinctYaw != nil {
          instruction = "Hold there."
        } else if abs(delta) <= Self.tolerance {
          instruction = view.request
        } else {
          instruction = delta > 0 ? "Turn a little farther." : "Turn back slightly."
        }
      } else {
        instruction = view.request
      }
    } else if isRecovering {
      instruction = "There aren’t enough clear views. Retake with a slower turn and steady arms."
    } else if lastPose == nil {
      instruction = "Hold your pose so we can find your angle."
    } else if !poseUsable {
      instruction = "Hold that position."
    } else {
      instruction = direction == nil ? "Turn slowly in place." : "Keep turning slowly."
    }
    return BodyCaptureTurnFeedback(completedViews: views, missingAngles: targets, instruction: instruction, captureComplete: false)
  }

  private func recoveryTargets(coverage: BodyCaptureCoverage) -> [Double] {
    guard let target = requestedAngles.first else { return coverage.missingAngles() }
    if coverage.canRecord(azimuth: target) { return requestedAngles }
    var closest: Double?
    var closestDistance = Self.targetWindow + Self.tolerance
    for view in coverage.viewpoints {
      let gap = BodyCaptureCoverage.duplicateAngle
      for angle in [view.azimuth - gap, view.azimuth + gap] {
        let distance = BodyCaptureCoverage.distance(angle, target)
        if distance < closestDistance, coverage.canRecord(azimuth: angle) {
          closest = BodyCaptureCoverage.normalized(angle)
          closestDistance = distance
        }
      }
    }
    guard let closest else { return [] }
    var targets = requestedAngles
    targets[0] = closest
    return targets
  }

  private func completedViews(coverage: BodyCaptureCoverage) -> Set<BodyCaptureView> {
    var completed = Set<BodyCaptureView>()
    for view in BodyCaptureView.allCases {
      let center = view.center(direction: direction ?? 1)
      var bins: UInt64 = 0
      var nearCenter = false
      for viewpoint in coverage.viewpoints {
        let distance = BodyCaptureCoverage.distance(viewpoint.azimuth, center)
        if distance <= .pi / 4 + Self.tolerance {
          bins |= 1 << BodyCaptureCoverage.bin(viewpoint.azimuth)
          nearCenter = nearCenter || distance <= .pi / 12 + Self.tolerance
          if nearCenter, bins.nonzeroBitCount >= 3 {
            completed.insert(view)
            break
          }
        }
      }
    }
    return completed
  }

  private mutating func losePose() {
    lastPose = nil
    poseUsable = false
    candidate = nil
    needsReacquisition = true
    if direction == nil { departure = 0 }
  }

  private mutating func observe(yaw: Double?, observedAt: TimeInterval, now: TimeInterval) {
    guard observedAt.isFinite, now.isFinite, observedAt <= now, now - observedAt <= Self.maximumAge,
          lastTimestamp.map({ observedAt > $0 }) ?? true else { losePose(); return }
    lastTimestamp = observedAt
    guard let yaw, yaw.isFinite else { losePose(); return }
    let pose = Pose(yaw: BodyCaptureCoverage.normalized(yaw), time: observedAt)
    if let old = lastPose {
      if let delta = Self.continuousDelta(from: old, to: pose, tooFast: &turningTooFast) {
        accept(pose, delta: delta, elapsed: pose.time - old.time)
        return
      }
      losePose()
    } else if !needsReacquisition, BodyCaptureCoverage.distance(pose.yaw, 0) <= Self.reacquisitionWindow + Self.tolerance {
      accept(pose, delta: 0, elapsed: 1)
      return
    }

    if var run = candidate, let delta = Self.continuousDelta(from: run.last, to: pose, tooFast: &turningTooFast) {
      let shift = BodyCaptureCoverage.signed(pose.yaw - run.anchor)
      run.minimum = min(run.minimum, shift)
      run.maximum = max(run.maximum, shift)
      if run.maximum - run.minimum <= Self.reacquisitionWindow + Self.tolerance {
        run.count += 1
        if run.count >= 3 {
          accept(pose, delta: delta, elapsed: pose.time - run.last.time)
        } else {
          run.last = pose
          candidate = run
        }
        return
      }
    }
    needsReacquisition = true
    candidate = Reacquisition(anchor: pose.yaw, last: pose)
  }

  private static func continuousDelta(from earlier: Pose, to later: Pose, tooFast: inout Bool) -> Double? {
    let elapsed = later.time - earlier.time
    let delta = BodyCaptureCoverage.signed(later.yaw - earlier.yaw)
    guard elapsed > 0, elapsed <= maximumAge, abs(delta) <= maximumJump + tolerance else { return nil }
    guard abs(delta) <= maximumRate * elapsed + tolerance else {
      tooFast = true
      return nil
    }
    return delta
  }

  private mutating func accept(_ pose: Pose, delta: Double, elapsed: TimeInterval) {
    lastPose = pose
    yawRate = delta / elapsed
    needsReacquisition = false
    candidate = nil
    if direction == nil {
      departure += delta
      if abs(departure) >= Self.maximumJump - Self.tolerance,
         BodyCaptureCoverage.distance(pose.yaw, 0) >= Self.maximumJump - Self.tolerance {
        direction = departure > 0 ? 1 : -1
      }
    }
    guard let direction, !returnedToFront else { return }
    let travel = BodyCaptureCoverage.normalized(pose.yaw * Double(direction))
    let step = delta * Double(direction)
    let nearFront = BodyCaptureCoverage.distance(travel, 0) <= Self.frontReturn + Self.tolerance
    if step < -Self.tolerance {
      if nearFront, sidesObserved == 1 { sidesObserved = 0 }
      return
    }
    if sidesObserved == 0, abs(travel - .pi / 2) <= .pi / 6 + Self.tolerance {
      sidesObserved = 1
    } else if sidesObserved == 1, abs(travel - 3 * .pi / 2) <= .pi / 6 + Self.tolerance {
      sidesObserved = 2
    } else if sidesObserved == 2, nearFront {
      returnedToFront = true
    }
  }
}
