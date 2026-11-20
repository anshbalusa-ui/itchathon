import Foundation
import simd

struct BodyCaptureGuideState {
  struct Placement {
    var transform: simd_float4x4
    var halfSize: SIMD2<Float>
  }

  var placement: Placement
  var capturedBins: Set<Int>
  var yaw: Double?
  var neededAngle: Double?
  var observedAt: TimeInterval

  static let segmentCount = BodyCaptureCoverage.binCount

  static func capturedBins(in coverage: BodyCaptureCoverage) -> Set<Int> {
    Set(coverage.viewpoints.map { BodyCaptureCoverage.bin($0.azimuth) })
  }

  func isFresh(now: TimeInterval) -> Bool {
    now.isFinite && observedAt.isFinite && (0...0.6).contains(now - observedAt)
  }

  static func markerPosition(angle: Double) -> SIMD3<Float> {
    let angle = Float(angle)
    return SIMD3(sin(angle) * 1.055, cos(angle) * 1.055, 0.01)
  }
}
