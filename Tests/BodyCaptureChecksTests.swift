import CoreImage
import CoreVideo
import ImageIO
import RealityKit
import CoreMotion
import simd
import UniformTypeIdentifiers
import XCTest
@testable import FitCheck

final class BodyCaptureChecksTests: XCTestCase {
  func testCalibrationNeedsStableSecondAndResetAcceptsNewScan() {
    var calibration = BodyCaptureCalibration()
    for step in 0..<4 {
      XCTAssertLessThan(calibration.update(observation(at: Double(step) * 0.25), now: Double(step) * 0.25), 1)
    }
    XCTAssertEqual(calibration.update(observation(at: 1), now: 1), 1)
    XCTAssertFalse(calibration.ready(now: 0.9))
    XCTAssertFalse(calibration.ready(now: 1.61))
    XCTAssertNil(calibration.lockBaseline(now: 1.61))
    let first = calibration.lockBaseline(now: 1.1)
    XCTAssertEqual(first?.radius, 1)
    XCTAssertEqual(first?.targetWorld, SIMD3<Float>(0, 0, 0))

    calibration.reset()
    for step in 0...4 {
      let at = 2 + Double(step) * 0.25
      calibration.update(observation(at: at, meters: 1.5, center: SIMD3<Float>(1, 2, 3)), now: at)
    }
    let second = calibration.lockBaseline(now: 3)
    XCTAssertEqual(second?.radius, 1.5)
    XCTAssertEqual(second?.targetWorld, SIMD3<Float>(1, 2, 3))
  }

  func testUnstableIncompleteAndStaleCalibrationCannotLock() {
    var calibration = BodyCaptureCalibration()
    for step in 0...4 {
      let at = Double(step) * 0.25
      calibration.update(observation(at: at, meters: step == 4 ? 1.3 : 1), now: at)
    }
    XCTAssertNil(calibration.lockBaseline(now: 1))

    calibration.reset()
    for step in 0..<4 {
      let at = Double(step) * 0.25
      calibration.update(observation(at: at, fullBody: false), now: at)
    }
    XCTAssertNil(calibration.lockBaseline(now: 0.75))

    calibration.reset()
    for step in 0...4 {
      let at = Double(step) * 0.25
      calibration.update(observation(at: at), now: at + (step == 4 ? 1 : 0))
    }
    XCTAssertNil(calibration.lockBaseline(now: 2))
    for step in 0...4 {
      let at = 3 + Double(step) * 0.25
      calibration.update(observation(at: at), now: at)
    }
    XCTAssertTrue(calibration.ready(now: 4))
    calibration.reset()
    XCTAssertNil(calibration.lockBaseline(now: 4))
  }

  func testCoverageNeedsUniqueDistributedViewpointsAndAlignedSubsetEvidence() {
    var coverage = BodyCaptureCoverage()
    for index in 0..<60 {
      XCTAssertTrue(coverage.record(sampleID: index, imageURL: URL(fileURLWithPath: "/body-capture-checks/\(index).jpg"),
                                    azimuth: Double(index) * 6 * .pi / 180, fullBody: index < 3))
    }
    XCTAssertTrue(coverage.hasCoverage())
    XCTAssertFalse(coverage.record(sampleID: 60, imageURL: URL(fileURLWithPath: "/body-capture-checks/60.jpg"),
                                   azimuth: 0, fullBody: true))
    XCTAssertFalse(coverage.hasCoverage(sampleIDs: Set(0..<56)))

    var missingSector = BodyCaptureCoverage()
    for index in 0..<72 where !(10..<18).contains(index) {
      XCTAssertTrue(missingSector.record(sampleID: index, imageURL: URL(fileURLWithPath: "/body-capture-checks/missing-\(index).jpg"),
                                         azimuth: Double(index) * 5 * .pi / 180, fullBody: index < 3))
    }
    XCTAssertFalse(missingSector.hasCoverage())

    var aligned = BodyCaptureCoverage()
    for index in 0..<72 {
      XCTAssertTrue(aligned.record(sampleID: index, imageURL: URL(fileURLWithPath: "/body-capture-checks/aligned-\(index).jpg"),
                                  azimuth: Double(index) * 5 * .pi / 180, fullBody: index < 3))
    }
    XCTAssertTrue(aligned.hasCoverage())
    XCTAssertFalse(aligned.hasCoverage(sampleIDs: Set(3..<72)))
    XCTAssertFalse(aligned.hasCoverage(sampleIDs: Set(0..<68)))
  }

  func testDepthPlaneRotatesClockwiseAndRejectsMalformedInput() {
    XCTAssertEqual(BodyCaptureDepthPlane.rotateClockwise([1, 2, 3, 4, 5, 6], width: 3, height: 2), [4, 1, 5, 2, 6, 3])
    XCTAssertNil(BodyCaptureDepthPlane.rotateClockwise([1, 2, 3], width: 2, height: 2))
  }

  func testUprightMaskMatchesRotatedPhotoAndFiltersNativeDepth() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let width = 6, height = 4
    let photoWidth = width * 16, photoHeight = height * 16
    let rgb = try pixels(kCVPixelFormatType_32BGRA, photoWidth, photoHeight)
    let depth = try pixels(kCVPixelFormatType_DepthFloat32, width, height)
    let confidence = try pixels(kCVPixelFormatType_OneComponent8, width, height)
    let mask = try pixels(kCVPixelFormatType_OneComponent8, height, width)
    try withPixels(rgb) { base, stride in
      for y in 0..<photoHeight {
        for x in 0..<photoWidth {
          let v: UInt8 = x < 16 && y < 16 ? 255 : 0
          base.advanced(by: y * stride + x * 4).storeBytes(of: SIMD4(v, v, v, 255), as: SIMD4<UInt8>.self)
        }
      }
    }
    try withPixels(depth) { base, stride in
      for y in 0..<height {
        for x in 0..<width {
          base.advanced(by: y * stride + x * 4).storeBytes(of: 1 + Float(y * width + x) / 100, as: Float.self)
        }
      }
    }
    try withPixels(confidence) { base, stride in memset(base, 2, stride * height) }
    try withPixels(mask) { base, stride in
      memset(base, 255, stride * width)
      base.storeBytes(of: UInt8(0), as: UInt8.self)
    }
    let context = CIContext()
    let photo = try BodyCapturePhotoWriter.portrait(rgb, context: context)
    XCTAssertEqual(photo.width, photoHeight)
    XCTAssertEqual(photo.height, photoWidth)
    XCTAssertGreaterThan(try luminance(photo, x: photo.width - 8), 220)
    XCTAssertLessThan(try luminance(photo, x: 8), 30)
    let imageURL = root.appendingPathComponent("frame.jpg")
    let depthURL = root.appendingPathComponent("frame.depth")
    let maskURL = root.appendingPathComponent("frame.png")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, photo, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    try BodyCaptureMaskPlane.write(BodyCaptureMaskPlane.portrait(mask, width: photo.width, height: photo.height, context: context), to: maskURL)
    try BodyCaptureDepthPlane.write(depth: depth, confidence: confidence, mask: mask, to: depthURL)
    let stored = BodyCaptureStoredSample(sampleID: 0, imageURL: imageURL, depthURL: depthURL, maskURL: maskURL,
                                         azimuth: 0, fullBody: true, gravity: CMAcceleration(x: 0, y: -1, z: 0))
    var coverage = BodyCaptureCoverage()
    XCTAssertTrue(coverage.record(sampleID: 0, imageURL: imageURL, azimuth: 0, fullBody: true))
    let archive = BodyCaptureArchive(samples: [stored], coverage: coverage)
    let input = try archive.makePhotogrammetryInput()
    let sample = try XCTUnwrap(input.samples.makeIterator().next())
    try input.validateReads()
    let readMask = try XCTUnwrap(sample.objectMask)
    XCTAssertEqual(CVPixelBufferGetWidth(readMask), photo.width)
    XCTAssertEqual(CVPixelBufferGetHeight(readMask), photo.height)
    try withPixels(readMask, flags: .readOnly) { base, _ in
      XCTAssertEqual(base.load(as: UInt8.self), 0)
      XCTAssertEqual(base.load(fromByteOffset: photo.width - 1, as: UInt8.self), 255)
    }
    try withPixels(XCTUnwrap(sample.depthDataMap), flags: .readOnly) { base, stride in
      XCTAssertEqual(base.load(as: Float.self), 0)
      XCTAssertEqual(base.load(fromByteOffset: 12, as: Float.self), 1, accuracy: 0.001)
      XCTAssertEqual(base.load(fromByteOffset: 5 * stride, as: Float.self), 1.23, accuracy: 0.001)
    }
    func assertRejected() throws {
      let invalid = try archive.makePhotogrammetryInput()
      XCTAssertNil(invalid.samples.makeIterator().next())
      XCTAssertThrowsError(try invalid.validateReads())
    }
    try FileManager.default.removeItem(at: maskURL)
    try assertRejected()
    try Data("not a mask".utf8).write(to: maskURL)
    try assertRejected()
    try FileManager.default.removeItem(at: maskURL)
    try BodyCaptureMaskPlane.write(BodyCaptureMaskPlane.portrait(mask, width: photo.height, height: photo.width, context: context), to: maskURL)
    try assertRejected()
  }

  private func pixels(_ format: OSType, _ width: Int, _ height: Int) throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, width, height, format, nil, &buffer), kCVReturnSuccess)
    return try XCTUnwrap(buffer)
  }

  private func withPixels(_ buffer: CVPixelBuffer, flags: CVPixelBufferLockFlags = [],
                          _ visit: (UnsafeMutableRawPointer, Int) -> Void) throws {
    XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, flags), kCVReturnSuccess)
    defer { CVPixelBufferUnlockBaseAddress(buffer, flags) }
    try visit(XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)), CVPixelBufferGetBytesPerRow(buffer))
  }

  private func luminance(_ image: CGImage, x: Int) throws -> UInt8 {
    let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: x, y: 0, width: 1, height: 1)))
    var rgba: [UInt8] = [0, 0, 0, 0]
    return try rgba.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                           bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      return bytes[0]
    }
  }

  private func observation(at time: TimeInterval, meters: Double = 1, center: SIMD3<Float> = .zero,
                           fullBody: Bool = true) -> BodyCaptureCalibrationObservation {
    BodyCaptureCalibrationObservation(observedAt: time, meters: meters, targetWorld: center,
                                      cameraTransform: matrix_identity_float4x4, referenceAxis: SIMD3<Float>(1, 0, 0),
                                      up: SIMD3<Float>(0, 1, 0), roll: 0,
                                      bounds: CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8),
                                      fullBody: fullBody, frontFacing: true, trackingNormal: true, stationary: true)
  }
}
