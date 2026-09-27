import XCTest
import CoreVideo
import simd
@testable import FitCheck

final class BodyScanTests: XCTestCase {

    func testScanConvertsSpansAndMarksAllFourMeasurementsAsUneditedBodyScan() throws {
        let profile = try GuidedBodyScanService().scan(BodyScanInput(
            chestWidth: 0.40, chestDepth: 0.30,
            waistWidth: 0.34, waistDepth: 0.28,
            shoulderWidth: 0.46, torsoLength: 0.62
        ))

        XCTAssertEqual(profile.chestCircumference, try BodyGeometry.circumference(width: 0.40, depth: 0.30), accuracy: 1e-12)
        XCTAssertEqual(profile.waistCircumference, try BodyGeometry.circumference(width: 0.34, depth: 0.28), accuracy: 1e-12)
        XCTAssertEqual(profile.shoulderWidth, 0.46, accuracy: 1e-12)
        XCTAssertEqual(profile.torsoLength, 0.62, accuracy: 1e-12)

        let expectedKeys: Set<String> = ["chestCircumference", "waistCircumference", "shoulderWidth", "torsoLength"]
        XCTAssertEqual(Set(profile.origins?.keys ?? Dictionary<String, MeasurementOrigin>().keys), expectedKeys)
        for key in expectedKeys {
            let origin = try XCTUnwrap(profile.origins?[key])
            XCTAssertEqual(origin.source, .bodyScan)
            XCTAssertFalse(origin.wasEdited)
            XCTAssertFalse(origin.verifiedWithTape)
            XCTAssertNil(origin.observedErrorMeters)
        }
    }

    func testScanRejectsInvalidAndOverflowingValuesForEveryInput() {
        let valid = [0.40, 0.30, 0.34, 0.28, 0.46, 0.62]
        for index in valid.indices {
            var values = valid
            values[index] = 0
            XCTAssertThrowsError(try GuidedBodyScanService().scan(input(values)), "zero at input \(index)")
            values[index] = .nan
            XCTAssertThrowsError(try GuidedBodyScanService().scan(input(values)), "NaN at input \(index)")
            values[index] = .infinity
            XCTAssertThrowsError(try GuidedBodyScanService().scan(input(values)), "infinity at input \(index)")
        }

        for indices in [[0, 1], [2, 3]] {
            var values = valid
            values[indices[0]] = .greatestFiniteMagnitude
            values[indices[1]] = .greatestFiniteMagnitude
            XCTAssertThrowsError(try GuidedBodyScanService().scan(input(values)), "overflow for pair \(indices)")
        }
    }

    func testDepthProjectionUsesIntrinsicsAndMetricDepth() throws {
        let intrinsics = simd_float3x3(columns: (
            SIMD3<Float>(1000, 0, 0),
            SIMD3<Float>(0, 1000, 0),
            SIMD3<Float>(500, 500, 1)
        ))
        let left = try DepthMeasurement.point(imagePoint: CGPoint(x: 0.4, y: 0.5), depthMeters: 2,
                                              intrinsics: intrinsics, imageSize: CGSize(width: 1000, height: 1000))
        let right = try DepthMeasurement.point(imagePoint: CGPoint(x: 0.6, y: 0.5), depthMeters: 2,
                                               intrinsics: intrinsics, imageSize: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(simd_distance(left, right), 0.4, accuracy: 1e-6)
    }

    func testDepthProjectionRejectsInvalidDepthBoundsAndIntrinsics() {
        let intrinsics = projectionIntrinsics(fx: 1000, fy: 1000, cx: 500, cy: 500)
        let imageSize = CGSize(width: 1000, height: 1000)
        for depth: Float in [0, -1, .nan, .infinity] {
            XCTAssertThrowsError(try DepthMeasurement.point(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMeters: depth,
                                                              intrinsics: intrinsics, imageSize: imageSize))
        }
        for point in [CGPoint(x: -0.01, y: 0.5), CGPoint(x: 1.01, y: 0.5), CGPoint(x: .nan, y: 0.5)] {
            XCTAssertThrowsError(try DepthMeasurement.point(imagePoint: point, depthMeters: 2,
                                                              intrinsics: intrinsics, imageSize: imageSize))
        }
        for bad in [projectionIntrinsics(fx: 0, fy: 1000, cx: 500, cy: 500),
                    projectionIntrinsics(fx: .nan, fy: 1000, cx: 500, cy: 500)] {
            XCTAssertThrowsError(try DepthMeasurement.point(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMeters: 2,
                                                              intrinsics: bad, imageSize: imageSize))
        }
    }

    func testViewportTransformMatchesPortraitCropAndInvertsToCameraPixels() throws {
        let imageSize = CGSize(width: 1000, height: 1000)
        let viewportSize = CGSize(width: 600, height: 800)
        let imageToView = CGAffineTransform(a: 0, b: 0.75, c: -4.0 / 3.0, d: 0, tx: 1.1666667, ty: 0.125)
        let transform = try DepthMeasurement.viewportTransform(imageSize: imageSize,
                                                                viewportSize: viewportSize,
                                                                imageToView: imageToView)
        let rawPixel = CGPoint(x: 320, y: 710)
        let normalized = CGPoint(x: rawPixel.x / imageSize.width, y: rawPixel.y / imageSize.height)
        let expectedNormalizedView = normalized.applying(imageToView)
        let expectedViewport = CGPoint(x: expectedNormalizedView.x * viewportSize.width,
                                       y: expectedNormalizedView.y * viewportSize.height)
        let actualViewport = rawPixel.applying(transform)
        XCTAssertEqual(actualViewport.x, expectedViewport.x, accuracy: 1e-4)
        XCTAssertEqual(actualViewport.y, expectedViewport.y, accuracy: 1e-4)

        let recovered = try DepthMeasurement.imagePoint(viewPoint: actualViewport,
                                                         viewportSize: viewportSize,
                                                         imageToView: imageToView)
        XCTAssertEqual(recovered.x, normalized.x, accuracy: 1e-6)
        XCTAssertEqual(recovered.y, normalized.y, accuracy: 1e-6)
    }

    func testViewportTransformRejectsInvalidGeometry() {
        let validImage = CGSize(width: 1000, height: 1000)
        let validViewport = CGSize(width: 600, height: 800)
        let identity = CGAffineTransform.identity
        XCTAssertThrowsError(try DepthMeasurement.viewportTransform(imageSize: validImage,
                                                                      viewportSize: .zero,
                                                                      imageToView: identity))
        XCTAssertThrowsError(try DepthMeasurement.viewportTransform(imageSize: .zero,
                                                                      viewportSize: validViewport,
                                                                      imageToView: identity))
        XCTAssertThrowsError(try DepthMeasurement.viewportTransform(imageSize: validImage,
                                                                      viewportSize: validViewport,
                                                                      imageToView: CGAffineTransform(a: 1, b: 2, c: 2, d: 4, tx: 0, ty: 0)))
    }

    func testDepthSamplingHonorsRowStrideAndReturnsCoherentClusterMedian() throws {
        let depth = try makeBuffer(width: 7, height: 7, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try makeBuffer(width: 7, height: 7, format: kCVPixelFormatType_OneComponent8)
        try withLocked(depth) { base, rowBytes in
            for y in 0..<7 {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<7 { row[x] = 2.0 + Float((x + y) % 3) * 0.01 }
            }
        }
        try withLocked(confidence) { base, rowBytes in
            for y in 0..<7 {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<7 { row[x] = 2 }
            }
        }
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(depth), CVPixelBufferGetWidth(depth) * MemoryLayout<Float>.stride)
        XCTAssertGreaterThan(CVPixelBufferGetBytesPerRow(confidence), CVPixelBufferGetWidth(confidence))
        let sampled = try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMap: depth, confidenceMap: confidence)
        XCTAssertEqual(sampled, 2.01, accuracy: 1e-6)
    }

    func testDepthSamplingRejectsInvalidDepthLowOrMissingConfidenceAndAmbiguousClusters() throws {
        let depth = try makeBuffer(width: 9, height: 9, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try makeBuffer(width: 9, height: 9, format: kCVPixelFormatType_OneComponent8)
        try fillDepth(depth, value: 2)
        try fillConfidence(confidence, value: 2)
        try fillDepth(depth, value: .nan, rect: CGRect(x: 2, y: 2, width: 5, height: 5))
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMap: depth, confidenceMap: confidence))

        try fillDepth(depth, value: 2)
        try fillConfidence(confidence, value: 0)
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMap: depth, confidenceMap: confidence))

        try fillDepth(depth, value: 2)
        try fillConfidence(confidence, value: 1)
        XCTAssertEqual(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5),
                                                    depthMap: depth, confidenceMap: confidence), 2, accuracy: 1e-6)
        try fillConfidence(confidence, value: 0)
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMap: depth, confidenceMap: confidence))

        try fillConfidence(confidence, value: 2)
        let undersizedConfidence = try makeBuffer(width: 5, height: 5, format: kCVPixelFormatType_OneComponent8)
        try fillConfidence(undersizedConfidence, value: 2)
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5),
                                                          depthMap: depth, confidenceMap: undersizedConfidence))

        try fillDepth(depth, value: 1)
        try fillDepth(depth, value: 3, rect: CGRect(x: 4, y: 0, width: 5, height: 9))
        try fillConfidence(confidence, value: 1)
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: 0.5, y: 0.5), depthMap: depth, confidenceMap: confidence)) { error in
            guard case BodyScanError.insufficientConfidence = error else {
                return XCTFail("Expected insufficient confidence for ambiguous depth clusters, got \(error)")
            }
        }

    }

    func testDepthSamplingBoundsNeighborhoodAtImageEdgesAndRejectsOutsidePoints() throws {
        let depth = try makeBuffer(width: 9, height: 9, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try makeBuffer(width: 9, height: 9, format: kCVPixelFormatType_OneComponent8)
        try fillDepth(depth, value: 2)
        try fillConfidence(confidence, value: 2)
        let edgeSample = try DepthMeasurement.sample(imagePoint: CGPoint(x: 0, y: 0.5), depthMap: depth, confidenceMap: confidence)
        XCTAssertEqual(edgeSample, 2, accuracy: 1e-6)
        XCTAssertThrowsError(try DepthMeasurement.sample(imagePoint: CGPoint(x: -0.01, y: 0.5), depthMap: depth, confidenceMap: confidence))
    }

    private func input(_ values: [Double]) -> BodyScanInput {
        BodyScanInput(chestWidth: values[0], chestDepth: values[1], waistWidth: values[2], waistDepth: values[3],
                      shoulderWidth: values[4], torsoLength: values[5])
    }

    private func projectionIntrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> simd_float3x3 {
        simd_float3x3(columns: (SIMD3<Float>(fx, 0, 0), SIMD3<Float>(0, fy, 0), SIMD3<Float>(cx, cy, 1)))
    }

    private func makeBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &buffer)
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(buffer)
    }

    private func withLocked(_ buffer: CVPixelBuffer, body: (UnsafeMutableRawPointer, Int) throws -> Void) throws {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        try body(try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer)), CVPixelBufferGetBytesPerRow(buffer))
    }

    private func fillDepth(_ buffer: CVPixelBuffer, value: Float, rect: CGRect = CGRect(x: 0, y: 0, width: 9, height: 9)) throws {
        try withLocked(buffer) { base, rowBytes in
            for y in Int(rect.minY)..<Int(rect.maxY) {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in Int(rect.minX)..<Int(rect.maxX) { row[x] = value }
            }
        }
    }

    private func fillConfidence(_ buffer: CVPixelBuffer, value: UInt8) throws {
        try withLocked(buffer) { base, rowBytes in
            for y in 0..<CVPixelBufferGetHeight(buffer) {
                let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
                for x in 0..<CVPixelBufferGetWidth(buffer) { row[x] = value }
            }
        }
    }
}
