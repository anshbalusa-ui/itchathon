@preconcurrency import ARKit
import CoreImage
import simd
import UIKit

struct GarmentCaptureResult: Sendable {
  var image: Data
  var dimensions: GarmentScanDimensions
}

actor GarmentDepthAnalyzer {
  private var landmarks: GarmentLandmarkDetector?
  private let context = CIContext()

  func analyze(_ frame: ARFrame) throws -> GarmentCaptureResult {
    try Task.checkCancellation()
    let camera = frame.camera
    guard case .normal = camera.trackingState, let sceneDepth = frame.sceneDepth,
          let confidence = sceneDepth.confidenceMap else { throw GarmentCaptureError.depth }
    guard abs(camera.transform.columns.2.y) > 0.96 else { throw GarmentCaptureError.angle }
    let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
    let factor = min(1, 1600 / source.extent.height)
    let resized = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    guard let image = context.createCGImage(resized, from: resized.extent) else { throw GarmentCaptureError.image }
    let foreground = try GarmentImageProcessor.foreground(image)
    let mask = try GarmentImageProcessor.smallMask(foreground.mask)
    var outline = try GarmentOutline.detect(mask: mask.bytes, width: mask.width, height: mask.height)
    if landmarks == nil { landmarks = try GarmentLandmarkDetector() }
    guard let landmarks else { throw GarmentCaptureError.image }
    let points = try landmarks.detect(in: image)
    let left = points[11], right = points[19], neck = points[1], hem = points[15]
    let bounds = outline.bounds.insetBy(dx: -0.025, dy: -0.025)
    guard [left, right, neck, hem, points[6], points[24]].allSatisfy({ bounds.contains($0) }),
          abs(left.y - right.y) < outline.bounds.height * 0.12,
          abs(left.x - right.x) > outline.bounds.width * 0.4,
          abs(left.x - right.x) < outline.bounds.width * 0.85,
          hem.y > max(left.y, right.y) + outline.bounds.height * 0.3,
          neck.y < min(left.y, right.y) else { throw GarmentCaptureError.shape }
    // Cross-check learned keypoints against the observed silhouette, not just model confidence.
    func nearEdge(_ point: CGPoint) -> Bool {
      let x = Int(point.x * Double(mask.width)), y = Int(point.y * Double(mask.height))
      let radius = max(3, mask.width / 30)
      var inside = false, outside = false
      for dy in -radius...radius { for dx in -radius...radius {
        let px = x + dx, py = y + dy
        guard px >= 0, px < mask.width, py >= 0, py < mask.height else { continue }
        if mask.bytes[py * mask.width + px] > 180 { inside = true } else { outside = true }
      } }
      return inside && outside
    }
    guard [left, right, neck, hem].allSatisfy(nearEdge) else { throw GarmentCaptureError.unclear }
    outline.widthLeft = left; outline.widthRight = right
    outline.top = neck
    outline.bottom = CGPoint(x: neck.x, y: hem.y)
    let depth = sceneDepth.depthMap
    CVPixelBufferLockBaseAddress(depth, .readOnly)
    CVPixelBufferLockBaseAddress(confidence, .readOnly)
    defer {
      CVPixelBufferUnlockBaseAddress(depth, .readOnly)
      CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
    }
    guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
          CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
          let depths = CVPixelBufferGetBaseAddress(depth), let confidences = CVPixelBufferGetBaseAddress(confidence) else { throw GarmentCaptureError.depth }
    let dw = CVPixelBufferGetWidth(depth), dh = CVPixelBufferGetHeight(depth)
    guard dw == CVPixelBufferGetWidth(confidence), dh == CVPixelBufferGetHeight(confidence) else { throw GarmentCaptureError.depth }
    let ds = CVPixelBufferGetBytesPerRow(depth), cs = CVPixelBufferGetBytesPerRow(confidence)
    let resolution = SIMD2(Float(camera.imageResolution.width), Float(camera.imageResolution.height))
    var heights: [Float] = [], sampled = 0
    for y in stride(from: 0, to: mask.height, by: 6) { for x in stride(from: 0, to: mask.width, by: 6) {
      guard mask.bytes[y * mask.width + x] > 230 else { continue }
      sampled += 1
      let u = Float(y) / Float(mask.height), v = 1 - Float(x) / Float(mask.width)
      let dx = min(dw - 1, Int(u * Float(dw))), dy = min(dh - 1, Int(v * Float(dh)))
      guard confidences.advanced(by: dy * cs).assumingMemoryBound(to: UInt8.self)[dx] == ARConfidenceLevel.high.rawValue else { continue }
      let z = depths.advanced(by: dy * ds).assumingMemoryBound(to: Float.self)[dx]
      guard z.isFinite, (0.3...2.5).contains(z) else { continue }
      let local = SIMD4((u * resolution.x - camera.intrinsics[2][0]) * z / camera.intrinsics[0][0],
                        -(v * resolution.y - camera.intrinsics[2][1]) * z / camera.intrinsics[1][1], -z, 1)
      heights.append((camera.transform * local).y)
    } }
    guard heights.count >= 35, heights.count * 2 >= sampled else { throw GarmentCaptureError.depth }
    heights.sort()
    let plane = heights[heights.count / 2]
    let errors = heights.map { abs($0 - plane) }.sorted()
    guard errors[errors.count * 9 / 10] < 0.025 else { throw GarmentCaptureError.depth }
    let projection = GarmentPlaneProjection(intrinsics: camera.intrinsics, cameraTransform: camera.transform,
                                            imageSize: resolution, planeHeight: plane)
    func distance(_ a: CGPoint, _ b: CGPoint) throws -> Double {
      Double(simd_distance(try projection.project(a), try projection.project(b)))
    }
    let dimensions = GarmentScanDimensions(bodyWidthM: try distance(outline.widthLeft, outline.widthRight),
                                           lengthM: try distance(outline.top, outline.bottom),
                                           sleeveSpanM: try distance(outline.sleeveLeft, outline.sleeveRight))
    guard dimensions.isValid else { throw GarmentCaptureError.shape }
    return GarmentCaptureResult(image: foreground.cutout, dimensions: dimensions)
  }
}
