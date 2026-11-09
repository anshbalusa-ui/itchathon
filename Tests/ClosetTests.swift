import CoreGraphics
import SceneKit
import XCTest
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
  func testCaptureConsensusNeedsThreeAgreeingFramesAndResetsOnOutlier() {
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
    XCTAssertNil(reopened.garments.first(where: { $0.id == photo.id })?.dimensions)
    let previousImage = reopened.imageURL(for: photo)
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
}
