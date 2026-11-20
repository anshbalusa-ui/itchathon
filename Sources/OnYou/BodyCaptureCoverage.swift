import Foundation
import simd

struct BodyCaptureViewpoint {
  let sampleID: Int
  let imageURL: URL
  let azimuth: Double
  let fullBody: Bool
}

struct BodyCaptureReconstructedPose {
  var translation: SIMD3<Float>
  var rotation: simd_quatf
}

enum BodyCaptureAlignment {
  case complete
  case missingAngles([Double])
  case invalid
}

struct BodyCaptureCoverage {
  static let minimumPhotos = 60
  static let minimumFullBodyPhotos = 3
  static let minimumBins = 32
  static let maximumGap = 20 * Double.pi / 180
  static let duplicateAngle = 3 * Double.pi / 180
  static let angleTolerance = 1e-6
  static let revolution = 2 * Double.pi
  static let binCount = 36
  private static let binWidth = revolution / Double(binCount)
  private(set) var viewpoints: [BodyCaptureViewpoint] = []
  private var sampleIDs = Set<Int>()
  private var imageURLs = Set<URL>()

  @discardableResult
  mutating func record(sampleID: Int, imageURL: URL, azimuth: Double, fullBody: Bool) -> Bool {
    guard sampleID >= 0, imageURL.isFileURL, azimuth.isFinite, !sampleIDs.contains(sampleID) else { return false }
    let file = imageURL.resolvingSymlinksInPath().standardizedFileURL
    guard !imageURLs.contains(file) else { return false }
    let angle = Self.normalized(azimuth)
    guard canRecord(normalizedAngle: angle) else { return false }
    sampleIDs.insert(sampleID)
    imageURLs.insert(file)
    viewpoints.append(BodyCaptureViewpoint(sampleID: sampleID, imageURL: file, azimuth: angle, fullBody: fullBody))
    return true
  }

  func canRecord(azimuth: Double) -> Bool {
    guard azimuth.isFinite else { return false }
    return canRecord(normalizedAngle: Self.normalized(azimuth))
  }

  private func canRecord(normalizedAngle angle: Double) -> Bool {
    viewpoints.allSatisfy { Self.separated(angle, from: $0.azimuth) }
  }

  func retaining(sampleIDs selectedIDs: Set<Int>) -> Self {
    var retained = Self()
    retained.viewpoints = viewpoints.filter { selectedIDs.contains($0.sampleID) }
    retained.sampleIDs = Set(retained.viewpoints.map(\.sampleID))
    retained.imageURLs = Set(retained.viewpoints.map(\.imageURL))
    return retained
  }

  func hasCoverage(sampleIDs selectedIDs: Set<Int>? = nil) -> Bool {
    guard let selected = selectedViewpoints(selectedIDs), selected.count >= Self.minimumPhotos else { return false }
    let fullBodyCount = selected.count(where: \.fullBody)
    guard fullBodyCount >= Self.minimumFullBodyPhotos else { return false }
    return Shape(angles: selected.map(\.azimuth), fullBodyCount: fullBodyCount).complete
  }

  func missingAngles(sampleIDs selectedIDs: Set<Int>? = nil) -> [Double] {
    guard let selected = selectedViewpoints(selectedIDs) else { return [] }
    let shape = Shape(angles: selected.map(\.azimuth), fullBodyCount: selected.count(where: \.fullBody))
    return shape.missingAngles(avoiding: shape.angles)
  }

  private func selectedViewpoints(_ selectedIDs: Set<Int>?) -> [BodyCaptureViewpoint]? {
    guard let selectedIDs else { return viewpoints }
    guard selectedIDs.isSubset(of: sampleIDs) else { return nil }
    return viewpoints.filter { selectedIDs.contains($0.sampleID) }
  }

  func alignedCoverage(poses: [Int: BodyCaptureReconstructedPose], rejectedIDs: Set<Int>) -> BodyCaptureAlignment {
    guard poses.keys.allSatisfy(sampleIDs.contains), rejectedIDs.isSubset(of: sampleIDs) else { return .invalid }

    var rays: [(position: SIMD3<Double>, bodyAngle: Double, fullBody: Bool)] = []
    rays.reserveCapacity(poses.count)
    var matrix = simd_double3x3(diagonal: .zero)
    var rhs = SIMD3<Double>.zero
    var up = SIMD3<Double>.zero
    for viewpoint in viewpoints where !rejectedIDs.contains(viewpoint.sampleID) {
      guard let pose = poses[viewpoint.sampleID] else { continue }
      let position = SIMD3<Double>(pose.translation)
      let length = simd_length(pose.rotation.vector)
      guard position.x.isFinite, position.y.isFinite, position.z.isFinite, length.isFinite, length > 1e-6 else {
        return .invalid
      }
      let rotation = simd_quatf(vector: pose.rotation.vector / length)
      let direction = SIMD3<Double>(rotation.act(SIMD3<Float>(0, 0, -1)))
      let projection = simd_double3x3(columns: (
        SIMD3<Double>(1, 0, 0) - direction * direction.x,
        SIMD3<Double>(0, 1, 0) - direction * direction.y,
        SIMD3<Double>(0, 0, 1) - direction * direction.z
      ))
      matrix = matrix + projection
      rhs += projection * position
      up += SIMD3<Double>(rotation.act(SIMD3<Float>(0, 1, 0)))
      rays.append((position, viewpoint.azimuth, viewpoint.fullBody))
    }

    let trace = matrix[0][0] + matrix[1][1] + matrix[2][2]
    let conditioning = abs(simd_determinant(matrix)) / max(1, trace * trace * trace)
    let upLength = simd_length(up)
    guard rays.count >= 3, conditioning >= 1e-6, upLength > 1e-6 * Double(rays.count) else { return .invalid }
    let center = simd_inverse(matrix) * rhs
    up /= upLength

    var reference: SIMD3<Double>?
    var angles: [Double] = []
    angles.reserveCapacity(rays.count)
    for ray in rays {
      let offset = ray.position - center
      let horizontal = offset - up * simd_dot(offset, up)
      let radius = simd_length(horizontal)
      guard radius.isFinite, radius > 1e-6 else { return .invalid }
      let radial = horizontal / radius
      if reference == nil { reference = radial }
      guard let reference else { return .invalid }
      angles.append(atan2(simd_dot(up, simd_cross(reference, radial)), simd_dot(reference, radial)))
    }

    func fit(sign: Double) -> (sign: Double, offset: Double, error: Double) {
      var sine = 0.0
      var cosine = 0.0
      for index in angles.indices {
        let difference = angles[index] - sign * rays[index].bodyAngle
        sine += sin(difference)
        cosine += cos(difference)
      }
      guard hypot(sine, cosine) > Self.angleTolerance else { return (sign, 0, .infinity) }
      let offset = atan2(sine, cosine)
      let residuals = angles.indices.map { Self.distance(angles[$0], sign * rays[$0].bodyAngle + offset) }.sorted()
      let median = (residuals[(residuals.count - 1) / 2] + residuals[residuals.count / 2]) / 2
      return (sign, offset, median)
    }

    let forward = fit(sign: 1)
    let backward = fit(sign: -1)
    let best = forward.error <= backward.error ? forward : backward
    guard best.error <= 25 * .pi / 180 + Self.angleTolerance else { return .invalid }

    // Bin reconstructed angles in the fitted front-relative basis, not by the stored yaw labels.
    let aligned = Shape(angles: angles.map { Self.normalized(($0 - best.offset) * best.sign) },
                        fullBodyCount: rays.count(where: { $0.fullBody }))
    guard aligned.maximumGap <= .pi + Self.angleTolerance else { return .invalid }
    if aligned.complete { return .complete }
    let missing = aligned.missingAngles(avoiding: rays.map(\.bodyAngle))
    return missing.isEmpty ? .invalid : .missingAngles(missing)
  }

  static func normalized(_ angle: Double) -> Double {
    let remainder = angle.truncatingRemainder(dividingBy: revolution)
    if remainder >= 0 { return remainder }
    let positive = remainder + revolution
    return positive == revolution ? 0 : positive
  }

  static func signed(_ angle: Double) -> Double {
    let angle = normalized(angle)
    return angle > .pi ? angle - revolution : angle
  }

  static func distance(_ lhs: Double, _ rhs: Double) -> Double {
    abs(signed(lhs - rhs))
  }

  static func bin(_ angle: Double) -> Int {
    min(binCount - 1, Int(normalized(angle + angleTolerance) / binWidth))
  }

  private static func separated(_ lhs: Double, from rhs: Double) -> Bool {
    distance(lhs, rhs) >= duplicateAngle - angleTolerance
  }

  private struct Gap {
    let start: Double
    let end: Double
    var width: Double { end - start }
    var midpoint: Double { (start + end) / 2 }
    var eligible: ClosedRange<Double> {
      min(midpoint, start + duplicateAngle)...max(midpoint, end - duplicateAngle)
    }
  }

  private struct Shape {
    let angles: [Double]
    let fullBodyCount: Int
    let bins: UInt64
    let maximumGap: Double

    init(angles: [Double], fullBodyCount: Int) {
      self.angles = angles.sorted()
      self.fullBodyCount = fullBodyCount
      bins = angles.reduce(0) { $0 | (1 << bin($1)) }
      var largest = revolution
      if let first = self.angles.first, let last = self.angles.last {
        largest = first + revolution - last
        for index in 1..<self.angles.count {
          largest = max(largest, self.angles[index] - self.angles[index - 1])
        }
      }
      maximumGap = largest
    }

    var complete: Bool {
      angles.count >= minimumPhotos && fullBodyCount >= minimumFullBodyPhotos &&
        bins.nonzeroBitCount >= minimumBins && maximumGap <= BodyCaptureCoverage.maximumGap + angleTolerance
    }

    func missingAngles(avoiding recorded: [Double]) -> [Double] {
      guard !complete else { return [] }
      var targets: [Double] = []
      var projectedBins = bins

      func request(_ preferred: Double, within interval: ClosedRange<Double>) {
        let center = min(interval.upperBound, max(interval.lowerBound, preferred))
        var best: Double?
        func consider(_ angle: Double) {
          guard interval.contains(angle),
                best.map({ abs(angle - center) < abs($0 - center) }) ?? true,
                recorded.allSatisfy({ separated(angle, from: $0) }) else { return }
          best = angle
        }
        consider(center)
        if best == nil {
          consider(interval.lowerBound)
          consider(interval.upperBound)
          for angle in recorded {
            let nearby = center + signed(angle - center)
            consider(nearby - duplicateAngle)
            consider(nearby + duplicateAngle)
          }
        }
        if let best, targets.allSatisfy({ separated(best, from: $0) }) {
          targets.append(normalized(best))
          projectedBins |= 1 << bin(best)
        }
      }

      let gaps = angles.indices.map { index in
        Gap(start: angles[index], end: index + 1 < angles.count ? angles[index + 1] : angles[0] + revolution)
      }
      let largeGaps = gaps.filter { $0.width > BodyCaptureCoverage.maximumGap + angleTolerance }
      for gap in largeGaps.sorted(by: { $0.width > $1.width }) {
        request(gap.midpoint, within: gap.eligible)
      }
      if bins.nonzeroBitCount < minimumBins {
        for index in 0..<binCount where projectedBins & (1 << index) == 0 {
          if projectedBins.nonzeroBitCount >= minimumBins { break }
          let start = Double(index) * binWidth
          request(start + binWidth / 2, within: start...(start + binWidth - 2 * angleTolerance))
        }
      }
      if largeGaps.isEmpty, bins.nonzeroBitCount >= minimumBins, angles.count < minimumPhotos,
         fullBodyCount >= minimumFullBodyPhotos {
        let eligibleGaps = gaps.filter { $0.width >= 2 * duplicateAngle - angleTolerance }
        var populations = [Int](repeating: 0, count: binCount)
        for angle in angles { populations[bin(angle)] += 1 }
        for gap in eligibleGaps.sorted(by: {
          let left = populations[bin($0.midpoint)]
          let right = populations[bin($1.midpoint)]
          return left == right ? $0.width > $1.width : left < right
        }) {
          if angles.count + targets.count >= minimumPhotos { break }
          request(gap.midpoint, within: gap.eligible)
        }
      }
      if fullBodyCount < minimumFullBodyPhotos {
        let front = 15 * Double.pi / 180
        request(0, within: -front...front)
      }
      return targets
    }
  }
}
