import CoreGraphics
import SceneKit
import XCTest
import UIKit
@testable import FitCheck

final class ClosetTests: XCTestCase {
  private enum ExpectedCaptureError {
    case angle, depth, shape
  }

  private func assertCaptureError(_ error: Error, matches expected: ExpectedCaptureError, file: StaticString = #filePath, line: UInt = #line) {
    guard let error = error as? GarmentCaptureError else {
      XCTFail("Unexpected non-garment capture error: \(error)", file: file, line: line)
      return
    }
    switch (expected, error) {
    case (.angle, .angle), (.depth, .depth), (.shape, .shape): break
    default: XCTFail("Unexpected garment capture rejection: \(error)", file: file, line: line)
    }
  }

  func testPhotoSaveKeepsTheOriginalBackgroundWithoutRecognition() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60)).image { context in
      UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
      UIColor.white.setFill(); context.fill(CGRect(x: 10, y: 10, width: 20, height: 40))
    }
    let original = try XCTUnwrap(image.pngData())
    let saved = try GarmentImageProcessor.importedPhoto(original)
    let reopened = try GarmentImageProcessor.normalized(saved)
    XCTAssertEqual(reopened.width, try GarmentImageProcessor.normalized(original).width)
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let corner = try XCTUnwrap(reopened.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
    context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    XCTAssertGreaterThan(pixel[2], 240)
    XCTAssertEqual(pixel[3], 255)
  }

  func testGuidanceUsesActualPreviewCropInsteadOfAssumingCameraFieldOfView() {
    let portrait = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
    let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
    let uncropped = GarmentPlaneProjection.viewportBounds(fromPortrait: portrait, displayTransform: rotate)
    XCTAssertEqual(uncropped.minX, portrait.minX, accuracy: 0.00001)
    XCTAssertEqual(uncropped.minY, portrait.minY, accuracy: 0.00001)
    let crop = rotate.concatenating(CGAffineTransform(a: 1.6, b: 0, c: 0, d: 1, tx: -0.3, ty: 0))
    let visible = GarmentPlaneProjection.viewportBounds(fromPortrait: portrait, displayTransform: crop)
    XCTAssertLessThan(visible.minX, 0)
    XCTAssertGreaterThan(visible.maxX, 1)
    var tracker = ScanGuidanceTracker()
    let feedback = tracker.update(ScanGuidanceSample(meters: 1, targetMeters: 1, bounds: visible, observedAt: 1), now: 1)
    XCTAssertEqual(feedback.direction, .farther)
  }

  func testGarmentGuidanceSeparatesOffCenterFromOversizedCropping() {
    var small = ScanGuidanceTracker()
    let aim = small.update(ScanGuidanceSample(meters: nil, targetMeters: nil,
                                               bounds: CGRect(x: -0.05, y: 0.3, width: 0.4, height: 0.4),
                                               observedAt: 30), now: 30)
    XCTAssertEqual(aim.direction, .left)

    var oversized = ScanGuidanceTracker()
    let back = oversized.update(ScanGuidanceSample(meters: nil, targetMeters: nil,
                                                    bounds: CGRect(x: -0.05, y: 0.3, width: 1.4, height: 0.4),
                                                    observedAt: 30), now: 30)
    XCTAssertEqual(back.direction, .farther)
  }

  func testGarmentGuidanceUsesViewportCoordinatesAndSignedOverheadTilt() throws {
    let points = [CGPoint(x: -10, y: 20), CGPoint(x: 110, y: 20),
                  CGPoint(x: 110, y: 180), CGPoint(x: -10, y: 180)]
    let bounds = try XCTUnwrap(GarmentCaptureGuidanceGeometry.viewportBounds(from: points, size: CGSize(width: 100, height: 200)))
    XCTAssertEqual(bounds.minX, -0.1, accuracy: 0.00001)
    XCTAssertEqual(bounds.maxX, 1.1, accuracy: 0.00001)
    XCTAssertEqual(bounds.minY, 0.1, accuracy: 0.00001)
    XCTAssertEqual(bounds.maxY, 0.9, accuracy: 0.00001)

    let display = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
    let expectedUV = CGPoint(x: 0.23, y: 0.67)
    let viewportPoint = expectedUV.applying(display)
    let nativeUV = try XCTUnwrap(GarmentCaptureGuidanceGeometry.nativeCameraUV(
      fromViewportPoint: viewportPoint, displayTransform: display))
    XCTAssertEqual(nativeUV.x, expectedUV.x, accuracy: 0.00001)
    XCTAssertEqual(nativeUV.y, expectedUV.y, accuracy: 0.00001)

    let level = simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 0, -1, 0),
                              SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(0, 0, 0, 1))
    let levelTilt = GarmentCaptureGuidanceGeometry.overheadTilt(transform: level)
    XCTAssertEqual(levelTilt.x, 0, accuracy: 0.00001)
    XCTAssertEqual(levelTilt.y, 0, accuracy: 0.00001)
    let angle = Float(0.2), cosine = cos(angle), sine = sin(angle)
    let rightTilt = simd_float4x4(SIMD4<Float>(cosine, -sine, 0, 0), SIMD4<Float>(0, 0, -1, 0),
                                  SIMD4<Float>(sine, cosine, 0, 0), SIMD4<Float>(0, 0, 0, 1))
    XCTAssertGreaterThan(GarmentCaptureGuidanceGeometry.overheadTilt(transform: rightTilt).x, 0)
    let downTilt = simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, sine, -cosine, 0),
                                 SIMD4<Float>(0, cosine, sine, 0), SIMD4<Float>(0, 0, 0, 1))
    XCTAssertGreaterThan(GarmentCaptureGuidanceGeometry.overheadTilt(transform: downTilt).y, 0)
  }

  func testLostAndStaleGarmentFramingNeverReportsReady() {

    var tracker = ScanGuidanceTracker()
    let centered = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
    XCTAssertEqual(tracker.update(ScanGuidanceSample(meters: 1, targetMeters: 1, bounds: centered,
                                                      observedAt: 20), now: 20).direction, .hold)
    let lost = tracker.update(ScanGuidanceSample(meters: 1, targetMeters: 1, bounds: nil,
                                                  observedAt: 20.1), now: 20.1)
    XCTAssertNotEqual(lost.direction, .hold)
    let stale = tracker.update(ScanGuidanceSample(meters: 1, targetMeters: 1, bounds: centered,
                                                   observedAt: 20.1), now: 20.8)
    XCTAssertEqual(stale.direction, .searching)
    XCTAssertNil(stale.meters)
  }

  func testMetricProjectionUsesDepthAndRejectsInvalidRays() throws {
    let intrinsics = simd_float3x3(SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(960, 720, 1))
    // A level camera looking down at a horizontal surface from a meter above it.
    let transform = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 1, 0, 1))
    let projection = GarmentPlaneProjection(intrinsics: intrinsics, cameraTransform: transform,
                                            imageSize: SIMD2(1920, 1440), planeHeight: 0)
    let leftUV = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: CGPoint(x: 0.3, y: 0.5))
    let rightUV = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: CGPoint(x: 0.7, y: 0.5))
    let left = try projection.project(nativeUV: leftUV)
    let right = try projection.project(nativeUV: rightUV)
    XCTAssertEqual(simd_distance(left, right), 0.576, accuracy: 0.0001)
    XCTAssertThrowsError(try GarmentPlaneProjection.nativeCameraUV(fromPortrait: CGPoint(x: .nan, y: 0.5)))
    var invalid = projection
    invalid.planeHeight = 2
    XCTAssertThrowsError(try invalid.project(nativeUV: CGPoint(x: 0.5, y: 0.5)))
  }
  func testCaptureSchedulerBoundsWorkAndProtectsRestartedSessions() throws {
    var scheduler = GarmentCaptureScheduler()
    scheduler.start()
    let first = try XCTUnwrap(scheduler.admit(timestamp: 1))
    XCTAssertNil(scheduler.admit(timestamp: 2))
    XCTAssertTrue(scheduler.owns(first))
    XCTAssertTrue(scheduler.finish(first, analysisDuration: 0.42))
    XCTAssertEqual(scheduler.lastAnalysisDuration, 0.42)
    XCTAssertNil(scheduler.admit(timestamp: 1))
    XCTAssertNil(scheduler.admit(timestamp: 1.699), "The existing minimum interval remains in force pending measured hardware evidence.")
    let interrupted = try XCTUnwrap(scheduler.admit(timestamp: 1.71))

    scheduler.stop()
    XCTAssertFalse(scheduler.owns(interrupted))
    XCTAssertNil(scheduler.admit(timestamp: 3))
    scheduler.start()
    let resumed = try XCTUnwrap(scheduler.admit(timestamp: 4))
    XCTAssertFalse(scheduler.finish(interrupted, analysisDuration: 9))
    XCTAssertTrue(scheduler.owns(resumed), "A stale completion must not release the resumed session's frame.")
    XCTAssertTrue(scheduler.finish(resumed, analysisDuration: 0.81))
    XCTAssertEqual(scheduler.lastAnalysisDuration, 0.81)
    XCTAssertNil(scheduler.admit(timestamp: 4), "A duplicate frame timestamp must not count as a distinct sample.")
    XCTAssertNil(scheduler.admit(timestamp: 4.699), "The original minimum interval remains in force.")
    XCTAssertNotNil(scheduler.admit(timestamp: 4.71))
  }
  func testCaptureConsensusNeedsThreeAgreeingFramesAndRejectsOutliers() {
    let base = GarmentScanDimensions(bodyWidthM: 0.5, lengthM: 0.7, sleeveSpanM: 0.8)
    var consensus = GarmentCaptureConsensus()
    XCTAssertNil(consensus.add(base))
    XCTAssertNil(consensus.add(base))
    XCTAssertEqual(consensus.add(base), base)
    XCTAssertEqual(consensus.count, 3)

    var outlier = base
    outlier.bodyWidthM = 0.6
    XCTAssertNil(consensus.add(outlier))
    XCTAssertEqual(consensus.count, 1)
    XCTAssertNil(consensus.add(outlier))
    XCTAssertEqual(consensus.add(outlier), outlier)
    consensus.reset()
    XCTAssertEqual(consensus.count, 0)
    XCTAssertNil(consensus.add(base))
  }

  func testCaptureConsensusPreservesGoodFramesThroughBriefMissesAndExpiresThem() {
    let base = GarmentScanDimensions(bodyWidthM: 0.5, lengthM: 0.7, sleeveSpanM: 0.8)
    var consensus = GarmentCaptureConsensus()
    XCTAssertNil(consensus.add(base, at: 1))
    consensus.miss(at: 2)
    XCTAssertEqual(consensus.count, 1)
    XCTAssertNil(consensus.add(base, at: 3))
    XCTAssertNil(consensus.add(.init(bodyWidthM: 0.7, lengthM: 0.9, sleeveSpanM: 1), at: 4))
    XCTAssertEqual(consensus.add(base, at: 5), base)
    consensus.miss(at: 18)
    XCTAssertEqual(consensus.count, 0)
    XCTAssertNil(consensus.add(base, at: 19))
    XCTAssertNil(consensus.add(base, at: 20))
    consensus.reset()
    XCTAssertNil(consensus.add(base, at: 21))
    XCTAssertEqual(consensus.count, 1)
  }

  func testClosedCollarAndSlightlyUnevenTorsoDoNotRequireANecklineHole() throws {
    let width = 192, height = 256
    var mask = [UInt8](repeating: 0, count: width * height)
    for y in 30..<220 { for x in 50..<142 { mask[y * width + x] = 255 } }
    for y in 40..<85 { for x in 20..<172 { mask[y * width + x] = 255 } }
    for y in 143..<147 { for x in 50..<60 { mask[y * width + x] = 0 } }
    let outline = try GarmentOutline.detect(mask: mask, width: width, height: height)
    XCTAssertEqual(outline.bounds.minY, 30.0 / 256, accuracy: 0.001)
  }

  func testProjectionRejectsCameraRayParallelToMetricPlane() {
    let intrinsics = simd_float3x3(SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(960, 720, 1))
    let projection = GarmentPlaneProjection(intrinsics: intrinsics, cameraTransform: matrix_identity_float4x4,
                                            imageSize: SIMD2(1920, 1440), planeHeight: 0)
    XCTAssertThrowsError(try projection.project(nativeUV: CGPoint(x: 0.5, y: 0.5))) { error in
      assertCaptureError(error, matches: .angle)
    }
  }


  func testSilhouetteRejectsNonShirtsAndClippedCaptures() throws {
    let width = 192, height = 256
    var mask = [UInt8](repeating: 0, count: width * height)
    for y in 30..<220 { for x in 50..<142 { mask[y * width + x] = 255 } }
    XCTAssertThrowsError(try GarmentOutline.detect(mask: mask, width: width, height: height))
    for y in 40..<85 { for x in 20..<172 { mask[y * width + x] = 255 } }
    // Visible neckline opening.
    for y in 30..<45 { for x in 80..<112 { mask[y * width + x] = 0 } }
    let outline = try GarmentOutline.detect(mask: mask, width: width, height: height)
    XCTAssertEqual(outline.widthRight.x - outline.widthLeft.x, 91.0 / 192, accuracy: 0.01)
    for y in 45..<70 { for x in 0..<20 { mask[y * width + x] = 255 } }
    XCTAssertThrowsError(try GarmentOutline.detect(mask: mask, width: width, height: height))
  }

  func testLandmarkValidationRejectsCollarBelowShoulders() {
    let outline = GarmentOutline(widthLeft: .zero, widthRight: .zero, top: .zero, bottom: .zero,
                                 sleeveLeft: .zero, sleeveRight: .zero,
                                 bounds: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
    var points = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 25)
    points[11] = CGPoint(x: 0.3, y: 0.3)
    points[19] = CGPoint(x: 0.7, y: 0.3)
    points[1] = CGPoint(x: 0.5, y: 0.2)
    points[15] = CGPoint(x: 0.5, y: 0.8)
    XCTAssertNoThrow(try GarmentLandmarkValidation.validate(points, against: outline))
    points[1] = CGPoint(x: 0.5, y: 0.4)
    XCTAssertThrowsError(try GarmentLandmarkValidation.validate(points, against: outline)) { error in
      assertCaptureError(error, matches: .shape)
    }
  }

  func testProjectionKeepsTypedDepthRejection() {
    let intrinsics = simd_float3x3(SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(960, 720, 1))
    let transform = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 1, 0, 1))
    let projection = GarmentPlaneProjection(intrinsics: intrinsics, cameraTransform: transform,
                                            imageSize: SIMD2(1920, 1440), planeHeight: 2)
    XCTAssertThrowsError(try projection.project(nativeUV: CGPoint(x: 0.5, y: 0.5))) { error in
      assertCaptureError(error, matches: .depth)
    }
  }

  func testPortraitCoordinatesMapToNativeUVBeforeProjection() throws {
    let intrinsics = simd_float3x3(SIMD3(1000, 0, 0), SIMD3(0, 1000, 0), SIMD3(960, 720, 1))
    let transform = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 1, 0, 1))
    let projection = GarmentPlaneProjection(intrinsics: intrinsics, cameraTransform: transform,
                                            imageSize: SIMD2(1920, 1440), planeHeight: 0)
    let uv = try GarmentPlaneProjection.nativeCameraUV(fromPortrait: CGPoint(x: 0.23, y: 0.67))
    XCTAssertEqual(uv.x, 0.67, accuracy: 0.000001)
    XCTAssertEqual(uv.y, 0.77, accuracy: 0.000001)
    let point = try projection.project(nativeUV: uv)
    XCTAssertEqual(point.x, 0.3264, accuracy: 0.0001)
    XCTAssertEqual(point.y, 0, accuracy: 0.0001)
    XCTAssertEqual(point.z, 0.3888, accuracy: 0.0001)
    XCTAssertThrowsError(try GarmentPlaneProjection.nativeCameraUV(fromPortrait: CGPoint(x: 1.01, y: 0.5)))

    for invalidUV in [CGPoint(x: .nan, y: 0.5), CGPoint(x: .infinity, y: 0.5),
                      CGPoint(x: -0.01, y: 0.5), CGPoint(x: 0.5, y: 1.01)] {
      XCTAssertThrowsError(try projection.project(nativeUV: invalidUV)) { error in
        assertCaptureError(error, matches: .depth)
      }
    }
  }

  func testComparisonRejectsBadDimensionsAndDoesNotClaimFit() {
    let base = GarmentScanDimensions(bodyWidthM: 0.5, lengthM: 0.7, sleeveSpanM: 0.8)
    XCTAssertTrue(base.isValid)
    XCTAssertEqual(GarmentScanDimensions.consensus([base, base, base]), base)
    XCTAssertNil(GarmentScanDimensions.consensus([base, base]))
    var drift = base
    drift.bodyWidthM += 0.014
    var driftAgain = drift
    driftAgain.bodyWidthM += 0.014
    XCTAssertTrue(base.agrees(with: drift))
    XCTAssertTrue(drift.agrees(with: driftAgain))
    XCTAssertNil(GarmentScanDimensions.consensus([base, drift, driftAgain]))
    var candidate = base
    candidate.bodyWidthM = 0.55; candidate.lengthM = 0.6
    XCTAssertEqual(candidate.comparison(to: base).map(\.1), ["Wider", "Shorter", "Similar"])
    XCTAssertFalse(candidate.agrees(with: base))
    candidate.bodyWidthM = .nan
    XCTAssertFalse(candidate.isValid)
    XCTAssertFalse(candidate.agrees(with: base))
    XCTAssertNil(ClosetGarment.productLink("javascript:alert(1)"))
    XCTAssertNil(ClosetGarment.productLink("https://user:password@example.com/shirt"))
    XCTAssertNotNil(ClosetGarment.productLink("https://example.com/shirt"))
  }

  @MainActor
  func testClosetPersistsReferencePhotoAndDeletionWithoutLosingOtherItems() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
      UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    let data = try XCTUnwrap(image.pngData())
    let store = ClosetStore(directory: root)
    let base = GarmentScanDimensions(bodyWidthM: 0.5, lengthM: 0.7, sleeveSpanM: 0.8)
    let scanned = try store.add(name: "Favorite", image: data, dimensions: base, productURL: nil)
    let photo = try store.add(name: "Wishlist", image: data, dimensions: nil, productURL: nil)
    store.setReference(scanned)
    XCTAssertEqual(store.reference?.id, scanned.id)
    store.setReference(photo)
    XCTAssertEqual(store.reference?.id, scanned.id)
    let reopened = ClosetStore(directory: root)
    XCTAssertEqual(reopened.garments, store.garments)
    let previousImage = reopened.imageURL(for: photo)
    XCTAssertThrowsError(try reopened.replaceCapture(for: photo, with: GarmentCaptureResult(image: Data("invalid".utf8), dimensions: base)))
    XCTAssertEqual(reopened.garments, store.garments)
    XCTAssertEqual(try Data(contentsOf: previousImage), data)
    try reopened.replaceCapture(for: photo, with: GarmentCaptureResult(image: data, dimensions: base))
    let updated = try XCTUnwrap(reopened.garments.first(where: { $0.id == photo.id }))
    XCTAssertEqual(updated.name, photo.name)
    XCTAssertEqual(updated.dimensions, base)
    XCTAssertNotEqual(reopened.imageURL(for: updated), previousImage)
    XCTAssertFalse(FileManager.default.fileExists(atPath: previousImage.path))
    XCTAssertEqual(ClosetStore(directory: root).garments, reopened.garments)
    reopened.delete(scanned)
    XCTAssertNil(reopened.reference)
    XCTAssertEqual(reopened.garments.map(\.id), [photo.id])
    XCTAssertTrue(FileManager.default.fileExists(atPath: reopened.imageURL(for: updated).path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.imageURL(for: scanned).path))
    reopened.delete(photo)
    XCTAssertTrue(reopened.garments.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.imageURL(for: updated).path),
                   "Deleting a retaken garment through an older selection must remove its current photo.")
    try Data("corrupt".utf8).write(to: root.appendingPathComponent("closet.json"))
    let corrupt = ClosetStore(directory: root)
    XCTAssertNotNil(corrupt.error)
    XCTAssertThrowsError(try corrupt.add(name: "New", image: data, dimensions: nil, productURL: nil))
    XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("closet.json")), Data("corrupt".utf8))
  }

  func testGarmentIQNativeInferenceMatchesConversionFixture() throws {
    let bundle = Bundle(for: ClosetTests.self)
    let url = try XCTUnwrap(bundle.url(forResource: "GarmentIQ-Shirt", withExtension: "jpg"))
    let image = try GarmentImageProcessor.normalized(Data(contentsOf: url))
    let points = try GarmentLandmarkDetector().detect(in: image)
    XCTAssertEqual(points.count, 25)
    // Reference coordinates from the quantized Core ML model's Python prediction.
    let expected: [(Int, Double, Double)] = [(1, 0.3368, 0.1380), (6, 0.1632, 0.1953), (11, 0.2326, 0.3568), (15, 0.4826, 0.8880), (19, 0.7118, 0.3776), (24, 0.7882, 0.1797)]
    for (index, x, y) in expected {
      XCTAssertEqual(points[index].x, x, accuracy: 0.025, "landmark \(index) x")
      XCTAssertEqual(points[index].y, y, accuracy: 0.025, "landmark \(index) y")
    }
  }

  #if !targetEnvironment(simulator)
  // Vision's foreground inference context is unavailable in the iOS simulator.
  func testRecognizedPhotoSurvivesTheCaptureToTryOnImageContract() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "GarmentIQ-Shirt", withExtension: "jpg"))
    let image = try GarmentImageProcessor.normalized(Data(contentsOf: url))
    let points = try GarmentLandmarkDetector().detect(in: image)
    let foreground = try GarmentImageProcessor.foreground(image)
    let mask = try GarmentImageProcessor.smallMask(foreground.mask)
    let outline = try GarmentOutline.detect(mask: mask.bytes, width: mask.width, height: mask.height)
    let dimensions = GarmentScanDimensions(bodyWidthM: 0.5, lengthM: 0.7, sleeveSpanM: 0.8)
    func candidate(_ frame: Double) -> GarmentCaptureCandidate {
      GarmentCaptureCandidate(cutout: foreground.cutout, points: points, outline: outline, dimensions: dimensions,
                              worldCorners: [], worldCenter: .zero,
                              timings: GarmentAnalysisTimings(foregroundSeconds: frame))
    }
    var consensus = GarmentCaptureConsensus()
    XCTAssertNil(consensus.add(candidate(1), at: 1))
    XCTAssertNil(consensus.add(candidate(2), at: 2))
    let accepted = try XCTUnwrap(consensus.add(candidate(3), at: 3))
    XCTAssertEqual(accepted.candidate.timings.foregroundSeconds, 3)
    XCTAssertEqual(accepted.dimensions, dimensions)

    let result = try await GarmentDepthAnalyzer().finalize(accepted.candidate, dimensions: accepted.dimensions)
    let evidence = try XCTUnwrap(result.pattern)
    XCTAssertTrue(evidence.matches(result.image))
    XCTAssertFalse(evidence.matches(Data("another frame".utf8)))
    let stored = try GarmentImageProcessor.normalized(result.image)
    let pattern = try TryOnBuilder.pattern(stored, landmarks: points.map { SIMD2(Float($0.x), Float($0.y)) })
    XCTAssertEqual(pattern.points.count, 25)
  }
  #endif
}
