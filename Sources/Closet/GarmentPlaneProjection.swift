import Foundation
import simd

/// Portrait image fractions -> calibrated camera ray -> horizontal garment plane.
struct GarmentPlaneProjection {
  var intrinsics: simd_float3x3
  var cameraTransform: simd_float4x4
  var imageSize: SIMD2<Float>
  var planeHeight: Float

  func project(_ point: CGPoint) throws -> SIMD3<Float> {
    guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y),
          imageSize.x > 0, imageSize.y > 0, intrinsics[0][0] > 0, intrinsics[1][1] > 0,
          planeHeight.isFinite else { throw GarmentCaptureError.depth }
    // ARKit's native sensor buffer is landscape; capture is explicitly portrait.
    let pixel = SIMD2(Float(point.y) * imageSize.x, (1 - Float(point.x)) * imageSize.y)
    let ray = SIMD4((pixel.x - intrinsics[2][0]) / intrinsics[0][0],
                    -(pixel.y - intrinsics[2][1]) / intrinsics[1][1], -1, 0)
    let direction = cameraTransform * ray
    let origin = cameraTransform.columns.3
    guard abs(direction.y) > 0.001 else { throw GarmentCaptureError.angle }
    let distance = (planeHeight - origin.y) / direction.y
    guard distance.isFinite, (0.3...2.5).contains(distance) else { throw GarmentCaptureError.depth }
    let result = origin + direction * distance
    guard [result.x, result.y, result.z].allSatisfy(\.isFinite) else { throw GarmentCaptureError.depth }
    return SIMD3(result.x, result.y, result.z)
  }
}
