import ARKit
import CoreMedia
import Foundation
import simd
import Vision

enum BodyCaptureFrameIssue: Equatable, Sendable {
  case missingPerson, multiplePeople, pose, depth
}

struct BodyCaptureFrameAssessment {
  let timestamp: TimeInterval
  let observedAt: TimeInterval
  var bounds: CGRect?
  var clipped = false
  var meters: Double?
  var torsoUV: CGPoint?
  var shoulderAxis: SIMD3<Float>?
  var hipAxis: SIMD3<Float>?
  var up: SIMD3<Float>?
  var frontFacing = false
  var fullBody = false
  var armsApart = false
  var mask: CVPixelBuffer?
  var issue: BodyCaptureFrameIssue?
  var sourcePersonWidth: Double = 0
}

/// Owns Vision requests and their buffers on the serial capture queue.
final class BodyCaptureFrameAnalyzer {
  private let pose2D = VNDetectHumanBodyPoseRequest()
  private let pose3D = VNDetectHumanBodyPose3DRequest()
  private let segmentation = VNGeneratePersonSegmentationRequest()
  private lazy var requests: [VNRequest] = [pose2D, pose3D, segmentation]
  private var format: CMVideoFormatDescription?

  init() {
    segmentation.qualityLevel = .accurate
    segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
  }

  func analyze(_ frame: ARFrame, viewport: CGSize, now: TimeInterval) throws -> BodyCaptureFrameAssessment {
    var intrinsics = frame.camera.intrinsics
    guard frame.timestamp.isFinite, now.isFinite,
          Self.finite(intrinsics.columns.0), Self.finite(intrinsics.columns.1), Self.finite(intrinsics.columns.2),
          intrinsics.columns.0.x > 0, intrinsics.columns.1.y > 0 else { throw FrameError.invalidSource }
    let image = frame.capturedImage
    let sample = try sampleBuffer(image, timestamp: frame.timestamp)
    let matrix = withUnsafeBytes(of: &intrinsics) { Data($0) }
    let handler = VNImageRequestHandler(cmSampleBuffer: sample, orientation: .right, options: [.cameraIntrinsics: matrix])
    try handler.perform(requests)

    var result = BodyCaptureFrameAssessment(timestamp: frame.timestamp, observedAt: now)
    let count2D = pose2D.results?.count ?? 0
    let count3D = pose3D.results?.count ?? 0
    guard count2D < 2, count3D < 2 else {
      result.issue = .multiplePeople
      return result
    }
    guard let mask = segmentation.results?.first?.pixelBuffer else {
      result.issue = count2D == 0 && count3D == 0 ? .missingPerson : .pose
      return result
    }
    return try Self.withPlane(mask, format: kCVPixelFormatType_OneComponent8, bytes: 1, invalid: .invalidMask) { plane in
      guard let box = Self.silhouette(plane) else {
        result.issue = .missingPerson
        return result
      }
      result.mask = mask
      result.bounds = Self.previewBounds(box, frame: frame, viewport: viewport)
      result.clipped = box.minX <= 0 || box.minY <= 0 || box.maxX >= 1 || box.maxY >= 1
      result.sourcePersonWidth = Double(box.width) * Double(CVPixelBufferGetHeight(image))
      let points = try pose2D.results?.first?.recognizedPoints(.all).compactMapValues { point in
        point.confidence >= 0.4 && Self.inImage(point.location) ? point.location : nil
      } ?? [:]
      result.fullBody = BodyCaptureEvidence.fullyVisible(points)
      if let leftShoulder = points[.leftShoulder], let rightShoulder = points[.rightShoulder],
         let leftHip = points[.leftHip], let rightHip = points[.rightHip] {
        let center = CGPoint(x: (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4,
                             y: (leftShoulder.y + rightShoulder.y + leftHip.y + rightHip.y) / 4)
        result.torsoUV = Self.nativeUV(center)
      }
      if let observation = pose3D.results?.first {
        try Self.assessPose(observation, points: points, result: &result)
      }
      let hasPose = result.shoulderAxis != nil && result.hipAxis != nil && result.up != nil && result.torsoUV != nil
      var depthValid = false
      if let sceneDepth = frame.sceneDepth, let confidence = sceneDepth.confidenceMap {
        let depth = try Self.measureDepth(sceneDepth.depthMap, confidence: confidence, mask: plane,
                                         box: box, torsoUV: result.torsoUV)
        depthValid = depth.valid
        result.meters = depth.meters
      }
      if !hasPose {
        result.issue = .pose
      } else if !depthValid || result.meters == nil {
        result.issue = .depth
      }
      return result
    }
  }

  private func sampleBuffer(_ image: CVPixelBuffer, timestamp: TimeInterval) throws -> CMSampleBuffer {
    if format.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: image) }) ?? true {
      let status = CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: image, formatDescriptionOut: &format)
      guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    guard let format else { throw FrameError.invalidSource }
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: timestamp, preferredTimescale: 1_000_000_000),
                                    decodeTimeStamp: .invalid)
    guard timing.presentationTimeStamp.isNumeric else { throw FrameError.invalidSource }
    var sample: CMSampleBuffer?
    let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: image,
                                                         formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    guard let sample else { throw FrameError.invalidSource }
    return sample
  }

  private typealias Points = [VNHumanBodyPoseObservation.JointName: CGPoint]

  private static func assessPose(_ observation: VNHumanBodyPose3DObservation, points: Points,
                                 result: inout BodyCaptureFrameAssessment) throws {
    let available = observation.availableJointNames
    func joint(_ name: VNHumanBodyPose3DObservation.JointName) throws -> SIMD3<Float>? {
      guard available.contains(name), let position = try availablePoint({ try observation.cameraRelativePosition(name) }) else { return nil }
      let p = position.columns.3
      let value = SIMD3(p.x, p.y, p.z)
      return finite(value) ? value : nil
    }
    if result.torsoUV == nil, available.contains(.spine),
       let point = try availablePoint({ try observation.pointInImage(.spine).location }), inImage(point) {
      result.torsoUV = nativeUV(point)
    }
    guard let ls = try joint(.leftShoulder), let rs = try joint(.rightShoulder),
          let lh = try joint(.leftHip), let rh = try joint(.rightHip) else { return }
    let shoulder = rs - ls, hip = rh - lh
    let up = (ls + rs - lh - rh) / 2
    guard let vertical = unit(up), let shoulderUnit = unit(shoulder), let hipUnit = unit(hip),
          let right = unit(shoulder - simd_dot(shoulder, vertical) * vertical) else { return }
    result.shoulderAxis = shoulder
    result.hipAxis = hip
    result.up = up

    if let nose = points[.nose], let leftEye = points[.leftEye], let rightEye = points[.rightEye],
       rightEye.x < nose.x, nose.x < leftEye.x,
       let view = unit(ls + rs + lh + rh) {
      result.frontFacing = abs(simd_dot(shoulderUnit, view)) <= 0.42 && abs(simd_dot(hipUnit, view)) <= 0.42
    }

    // At profile the far arm may be hidden in 2D; corroborate at least one arm and test both in body space.
    let armVisible = (points[.leftElbow] != nil && points[.leftWrist] != nil) ||
                     (points[.rightElbow] != nil && points[.rightWrist] != nil)
    guard armVisible, let le = try joint(.leftElbow), let lw = try joint(.leftWrist),
          let re = try joint(.rightElbow), let rw = try joint(.rightWrist) else { return }
    let shoulderWidth = simd_length(shoulder)
    let height = simd_length(up)
    func separated(shoulder: SIMD3<Float>, hip: SIMD3<Float>, elbow: SIMD3<Float>, wrist: SIMD3<Float>, sign: Float) -> Bool {
      func clearance(_ joint: SIMD3<Float>) -> Float {
        let level = min(1, max(0, simd_dot(shoulder - joint, vertical) / height))
        let side = shoulder + level * (hip - shoulder)
        return sign * simd_dot(joint - side, right)
      }
      return simd_length(elbow - shoulder) >= shoulderWidth * 0.15 && simd_length(wrist - elbow) >= shoulderWidth * 0.15 &&
        clearance(elbow) >= shoulderWidth * 0.08 && clearance(wrist) >= shoulderWidth * 0.12
    }
    result.armsApart = separated(shoulder: ls, hip: lh, elbow: le, wrist: lw, sign: -1) &&
                       separated(shoulder: rs, hip: rh, elbow: re, wrist: rw, sign: 1)
  }

  private static func availablePoint<T>(_ read: () throws -> T) throws -> T? {
    do { return try read() }
    catch let error as NSError where error.domain == VNErrorDomain && error.code == VNErrorCode.dataUnavailable.rawValue {
      return nil
    }
  }

  private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }

  private static func unit(_ value: SIMD3<Float>) -> SIMD3<Float>? {
    let length = simd_length(value)
    return length.isFinite && length > 1e-5 ? value / length : nil
  }

  private static func inImage(_ point: CGPoint) -> Bool { (0...1).contains(point.x) && (0...1).contains(point.y) }

  private static func nativeUV(_ visionPoint: CGPoint) -> CGPoint { CGPoint(x: 1 - visionPoint.y, y: 1 - visionPoint.x) }

  private static func previewBounds(_ portrait: CGRect, frame: ARFrame, viewport: CGSize) -> CGRect? {
    guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0 else { return nil }
    let native = CGRect(x: portrait.minY, y: 1 - portrait.maxX, width: portrait.height, height: portrait.width)
    let transform = frame.displayTransform(for: .portrait, viewportSize: viewport)
    let determinant = transform.a * transform.d - transform.b * transform.c
    guard determinant.isFinite, abs(determinant) > 1e-6, transform.tx.isFinite, transform.ty.isFinite else { return nil }
    let bounds = native.applying(transform)
    guard bounds.minX.isFinite, bounds.minY.isFinite, bounds.width.isFinite, bounds.height.isFinite else { return nil }
    return bounds
  }

  private enum FrameError: Error {
    case invalidSource, invalidMask, invalidDepth, invalidConfidence
  }

  private struct Plane {
    let base: UnsafeRawPointer
    let width: Int
    let height: Int
    let stride: Int
  }

  private static func withPlane<T>(_ buffer: CVPixelBuffer, format: OSType, bytes: Int, invalid: FrameError,
                                   read: (Plane) throws -> T) throws -> T {
    guard CVPixelBufferGetPixelFormatType(buffer) == format, !CVPixelBufferIsPlanar(buffer) else { throw invalid }
    let status = CVPixelBufferLockBaseAddress(buffer, .readOnly)
    guard status == kCVReturnSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer), width > 0, height > 0,
          stride > 0, width <= stride / bytes, height <= CVPixelBufferGetDataSize(buffer) / stride else { throw invalid }
    return try read(Plane(base: UnsafeRawPointer(base), width: width, height: height, stride: stride))
  }

  private static func silhouette(_ mask: Plane) -> CGRect? {
    var minX = mask.width, minY = mask.height, maxX = -1, maxY = -1
    for y in 0..<mask.height {
      let row = mask.base.advanced(by: y * mask.stride).assumingMemoryBound(to: UInt8.self)
      for x in 0..<mask.width where row[x] >= 128 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = y
      }
    }
    guard minX <= maxX, minY <= maxY else { return nil }
    return CGRect(x: Double(minX) / Double(mask.width), y: Double(minY) / Double(mask.height),
                  width: Double(maxX + 1 - minX) / Double(mask.width), height: Double(maxY + 1 - minY) / Double(mask.height))
  }

  private static func measureDepth(_ depthBuffer: CVPixelBuffer, confidence confidenceBuffer: CVPixelBuffer, mask: Plane,
                                   box: CGRect, torsoUV: CGPoint?) throws -> (valid: Bool, meters: Double?) {
    try withPlane(depthBuffer, format: kCVPixelFormatType_DepthFloat32, bytes: 4, invalid: .invalidDepth) { depth in
      try withPlane(confidenceBuffer, format: kCVPixelFormatType_OneComponent8, bytes: 1, invalid: .invalidConfidence) { confidence in
        guard depth.width == confidence.width, depth.height == confidence.height else { throw FrameError.invalidConfidence }
        let medium = UInt8(ARConfidenceLevel.medium.rawValue)
        func depthAt(_ x: Int, _ y: Int) -> Float? {
          guard confidence.base.load(fromByteOffset: y * confidence.stride + x, as: UInt8.self) >= medium else { return nil }
          let value = depth.base.loadUnaligned(fromByteOffset: y * depth.stride + x * MemoryLayout<Float>.stride, as: Float.self)
          return (0.2...3).contains(value) ? value : nil
        }
        // Rotate normalized native depth pixel centers clockwise into the upright mask. No resampled plane is needed.
        func maskColumn(_ y: Int) -> Int { (2 * (depth.height - y) - 1) * mask.width / (2 * depth.height) }
        func maskRow(_ x: Int) -> Int { (2 * x + 1) * mask.height / (2 * depth.width) }
        func isPerson(column: Int, row: Int) -> Bool { mask.base.load(fromByteOffset: row * mask.stride + column, as: UInt8.self) >= 128 }
        let longest = max(depth.width, depth.height)
        let divisor = max(1, (longest + 159) / 160)
        var counts = SIMD3<Int>.zero, valid = SIMD3<Int>.zero
        for startY in stride(from: 0, to: depth.height, by: divisor) {
          let y = min(depth.height - 1, startY + divisor / 2)
          let column = maskColumn(y)
          for startX in stride(from: 0, to: depth.width, by: divisor) {
            let x = min(depth.width - 1, startX + divisor / 2)
            guard isPerson(column: column, row: maskRow(x)) else { continue }
            let portraitY = (Double(x) + 0.5) / Double(depth.width)
            let third = min(2, max(0, Int(3 * (portraitY - box.minY) / box.height)))
            counts[third] += 1
            if depthAt(x, y) != nil { valid[third] += 1 }
          }
        }
        let total = counts.x + counts.y + counts.z, usable = valid.x + valid.y + valid.z
        let covered = usable >= 30 && usable * 5 >= total * 3 &&
          valid.x >= 8 && valid.x * 5 >= counts.x * 2 &&
          valid.y >= 8 && valid.y * 5 >= counts.y * 2 &&
          valid.z >= 8 && valid.z * 5 >= counts.z * 2
        guard let torsoUV else { return (covered, nil) }
        let meters: Double? = withUnsafeTemporaryAllocation(of: Float.self, capacity: 81) { samples in
          var count = 0
          for row in -4...4 {
            for column in -4...4 {
              let u = torsoUV.x + Double(column) * min(box.height / 16, 0.05)
              let v = torsoUV.y + Double(row) * min(box.width / 8, 0.05)
              guard (0..<1).contains(u), (0..<1).contains(v) else { continue }
              let x = Int(u * Double(depth.width)), y = Int(v * Double(depth.height))
              guard isPerson(column: maskColumn(y), row: maskRow(x)), let value = depthAt(x, y) else { continue }
              samples[count] = value
              count += 1
            }
          }
          guard count >= 12 else { return nil }
          var validSamples = UnsafeMutableBufferPointer(start: samples.baseAddress, count: count)
          validSamples.sort()
          return Double(validSamples[count / 2])
        }
        return (covered, meters)
      }
    }
  }
}
