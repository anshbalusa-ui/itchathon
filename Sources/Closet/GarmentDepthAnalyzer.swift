@preconcurrency import ARKit
import CoreImage
import simd
import UIKit

enum GarmentAnalysisStage: Sendable {
  case recognizing, landmarks, metricDepth, projecting
}

struct GarmentAnalysisTimings: Sendable, Equatable {
  var foregroundSeconds: TimeInterval = 0
  var silhouetteSeconds: TimeInterval = 0
  var landmarkSeconds: TimeInterval = 0
  var landmarkModelLoadMS: Double = 0
  var landmarkPreprocessingMS: Double = 0
  var landmarkPredictionMS: Double = 0
  var landmarkDecodingMS: Double = 0
  var depthSeconds: TimeInterval = 0
  var projectionSeconds: TimeInterval = 0
  var totalSeconds: TimeInterval = 0
}

struct GarmentCaptureResult: Sendable {
  var image: Data
  var dimensions: GarmentScanDimensions
  var pattern: GarmentPatternEvidence?
  var timings: GarmentAnalysisTimings?

  init(image: Data, dimensions: GarmentScanDimensions,
       pattern: GarmentPatternEvidence? = nil, timings: GarmentAnalysisTimings? = nil) {
    self.image = image
    self.dimensions = dimensions
    self.pattern = pattern
    self.timings = timings
  }
}

struct ValidatedGarmentLandmarks {
  var left: CGPoint
  var right: CGPoint
  var neck: CGPoint
  var hem: CGPoint
}

enum GarmentLandmarkValidation {
  static func validate(_ points: [CGPoint], against outline: GarmentOutline) throws -> ValidatedGarmentLandmarks {
    guard points.count > 24 else { throw GarmentCaptureError.shape }
    let left = points[11], right = points[19], neck = points[1], hem = points[15]
    let bounds = outline.bounds.insetBy(dx: -0.025, dy: -0.025)
    guard [left, right, neck, hem, points[6], points[24]].allSatisfy({ bounds.contains($0) }),
          abs(left.y - right.y) < outline.bounds.height * 0.12,
          abs(left.x - right.x) > outline.bounds.width * 0.4,
          abs(left.x - right.x) < outline.bounds.width * 0.85,
          hem.y > max(left.y, right.y) + outline.bounds.height * 0.3,
          neck.y < min(left.y, right.y) else { throw GarmentCaptureError.shape }
    return ValidatedGarmentLandmarks(left: left, right: right, neck: neck, hem: hem)
  }
}

actor GarmentDepthAnalyzer {
  private let context = CIContext()

  func analyze(_ frame: ARFrame, onStage: @Sendable (GarmentAnalysisStage) -> Void = { _ in }) async throws -> GarmentCaptureResult {
    let started = ProcessInfo.processInfo.systemUptime
    var timings = GarmentAnalysisTimings()
    try Task.checkCancellation()
    onStage(.recognizing)
    let camera = frame.camera
    guard case .normal = camera.trackingState, let sceneDepth = frame.sceneDepth,
          let confidence = sceneDepth.confidenceMap else { throw GarmentCaptureError.depth }
    guard abs(camera.transform.columns.2.y) > 0.96 else { throw GarmentCaptureError.angle }
    // RGB is rotated for portrait Vision; depth and intrinsics remain native landscape.
    let source = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
    let factor = min(1, 1600 / source.extent.height)
    let resized = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
    guard let image = context.createCGImage(resized, from: resized.extent) else { throw GarmentCaptureError.image }
    let foregroundStarted = ProcessInfo.processInfo.systemUptime
    let foreground = try GarmentImageProcessor.foreground(image)
    try Task.checkCancellation()
    timings.foregroundSeconds = ProcessInfo.processInfo.systemUptime - foregroundStarted
    let silhouetteStarted = ProcessInfo.processInfo.systemUptime
    let mask = try GarmentImageProcessor.smallMask(foreground.mask)
    var outline = try GarmentOutline.detect(mask: mask.bytes, width: mask.width, height: mask.height)
    timings.silhouetteSeconds = ProcessInfo.processInfo.systemUptime - silhouetteStarted
    onStage(.landmarks)
    try Task.checkCancellation()
    let landmarkStarted = ProcessInfo.processInfo.systemUptime
    let detection = try await GarmentLandmarkService.shared.detect(in: image)
    try Task.checkCancellation()
    timings.landmarkSeconds = ProcessInfo.processInfo.systemUptime - landmarkStarted
    timings.landmarkModelLoadMS = detection.timing.modelLoadMS
    timings.landmarkPreprocessingMS = detection.timing.preprocessingMS
    timings.landmarkPredictionMS = detection.timing.predictionMS
    timings.landmarkDecodingMS = detection.timing.decodingMS
    let garmentLandmarks = try GarmentLandmarkValidation.validate(detection.points, against: outline)
    let left = garmentLandmarks.left, right = garmentLandmarks.right
    let neck = garmentLandmarks.neck, hem = garmentLandmarks.hem
    try Task.checkCancellation()
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
    try Task.checkCancellation()
    onStage(.metricDepth)
    let depthStarted = ProcessInfo.processInfo.systemUptime
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
      let portraitPoint = CGPoint(x: Double(x) / Double(mask.width), y: Double(y) / Double(mask.height))
      let uv = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: portraitPoint)
      let nativeX = Float(uv.x), nativeY = Float(uv.y)
      let dx = min(dw - 1, Int(uv.x * Double(dw))), dy = min(dh - 1, Int(uv.y * Double(dh)))
      guard confidences.advanced(by: dy * cs).assumingMemoryBound(to: UInt8.self)[dx] == ARConfidenceLevel.high.rawValue else { continue }
      let z = depths.advanced(by: dy * ds).assumingMemoryBound(to: Float.self)[dx]
      guard z.isFinite, (0.3...2.5).contains(z) else { continue }
      let local = SIMD4((nativeX * resolution.x - camera.intrinsics[2][0]) * z / camera.intrinsics[0][0],
                        -(nativeY * resolution.y - camera.intrinsics[2][1]) * z / camera.intrinsics[1][1], -z, 1)
      heights.append((camera.transform * local).y)
    } }
    guard heights.count >= 35, heights.count * 2 >= sampled else { throw GarmentCaptureError.depth }
    heights.sort()
    let plane = heights[heights.count / 2]
    let errors = heights.map { abs($0 - plane) }.sorted()
    guard errors[errors.count * 9 / 10] < 0.025 else { throw GarmentCaptureError.depth }
    timings.depthSeconds = ProcessInfo.processInfo.systemUptime - depthStarted
    onStage(.projecting)
    try Task.checkCancellation()
    let projectionStarted = ProcessInfo.processInfo.systemUptime
    let projection = GarmentPlaneProjection(intrinsics: camera.intrinsics, cameraTransform: camera.transform,
                                            imageSize: resolution, planeHeight: plane)
    func distance(_ a: CGPoint, _ b: CGPoint) throws -> Double {
      let leftUV = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: a)
      let rightUV = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: b)
      return Double(simd_distance(try projection.project(nativeUV: leftUV), try projection.project(nativeUV: rightUV)))
    }
    let dimensions = GarmentScanDimensions(bodyWidthM: try distance(outline.widthLeft, outline.widthRight),
                                           lengthM: try distance(outline.top, outline.bottom),
                                           sleeveSpanM: try distance(outline.sleeveLeft, outline.sleeveRight))
    guard dimensions.isValid else { throw GarmentCaptureError.shape }
    timings.projectionSeconds = ProcessInfo.processInfo.systemUptime - projectionStarted
    let pattern = try GarmentPatternEvidence.validate(image: foreground.cutout, points: detection.points, outline: outline)
    timings.totalSeconds = ProcessInfo.processInfo.systemUptime - started
    return GarmentCaptureResult(image: foreground.cutout, dimensions: dimensions, pattern: pattern, timings: timings)
  }
}
