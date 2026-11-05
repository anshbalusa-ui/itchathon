#if DEBUG
import CoreGraphics
import XCTest
import CoreVideo
@testable import FitCheck

final class PersonDepthAlignmentTests: XCTestCase {
    func testAllNativeToUprightRotationsInvertVisionCoordinates() {
        let p = CGPoint(x: 0.23, y: 0.71)
        let cases: [(ScanImageRotation, ScanPoint)] = [
            (.up, ScanPoint(x: 0.23, y: 0.29)),
            (.right, ScanPoint(x: 0.29, y: 0.77)),
            (.down, ScanPoint(x: 0.77, y: 0.71)),
            (.left, ScanPoint(x: 0.71, y: 0.23))
        ]
        for (rotation, expected) in cases {
            let actual = AvatarFrameAnalyzer.nativeTopLeft(p, rotation: rotation)
            XCTAssertEqual(actual.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(actual.y, expected.y, accuracy: 1e-12)
        }
    }

    func testPersonAssociatedDepthIgnoresValidBackground() throws {
        let fixture = makeFixture()
        let result = try evaluate(fixture)
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.representativeDepth ?? 0, 2, accuracy: 0.001)
    }

    func testPersonWithoutDepthIsRejectedDespiteValidBackground() throws {
        var f = makeFixture()
        f.depth = [Float](repeating: 3, count: 64 * 64)
        for y in 12..<52 { for x in 20..<44 { f.depth[y * 64 + x] = .nan } }
        let result = try evaluate(f)
        XCTAssertEqual(result.rejection, .insufficientPersonDepth)
    }
    func testAppleEvidenceExposesBorrowedNativePixelBuffers() throws {
        let depth = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_OneComponent8)
        let mask = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_OneComponent8)
        try fill(depth, float: 1.75)
        try fill(confidence, byte: 2)
        try fill(mask, byte: 255)
        let evidence = AppleScanEvidence(depth: depth, confidence: confidence, mask: mask)
        try evidence.withPlanes { d, c, m in
            XCTAssertEqual(d.width, 8); XCTAssertEqual(d.height, 8)
            XCTAssertEqual(d.value(x: 4, y: 4), 1.75, accuracy: 0.001)
            XCTAssertEqual(c.value(x: 4, y: 4), 2)
            XCTAssertEqual(m.value(x: 4, y: 4), 255)
        }
    }

    private func pixelBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, nil, &result), kCVReturnSuccess)
        return try XCTUnwrap(result)
    }

    private func fill(_ buffer: CVPixelBuffer, float: Float) throws {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let row = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            let values = base.advanced(by: y * row).assumingMemoryBound(to: Float.self)
            for x in 0..<CVPixelBufferGetWidth(buffer) { values[x] = float }
        }
    }

    private func fill(_ buffer: CVPixelBuffer, byte: UInt8) throws {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let row = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<CVPixelBufferGetHeight(buffer) {
            let values = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
            for x in 0..<CVPixelBufferGetWidth(buffer) { values[x] = byte }
        }
    }
    func testAppleEvidenceRejectsMalformedPixelFormats() throws {
        let depth = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_DepthFloat32)
        let confidence = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_OneComponent8)
        let badMask = try pixelBuffer(width: 8, height: 8, format: kCVPixelFormatType_DepthFloat32)
        XCTAssertThrowsError(try AppleScanEvidence(depth: depth, confidence: confidence, mask: badMask).withPlanes { _, _, _ in })
    }

    func testOrientationRequiresConcordantFrontEvidenceOrDefensibleSideAxis() {
        var landmarks: [ScanJoint: ScanPoint] = [
            .nose: ScanPoint(x: 0.5, y: 0.2), .leftEye: ScanPoint(x: 0.46, y: 0.18), .rightEye: ScanPoint(x: 0.54, y: 0.18),
            .leftShoulder: ScanPoint(x: 0.4, y: 0.35), .rightShoulder: ScanPoint(x: 0.6, y: 0.35),
            .leftHip: ScanPoint(x: 0.43, y: 0.58), .rightHip: ScanPoint(x: 0.57, y: 0.58)
        ]
        let frontShoulder = PersonDepthAligner.AxisAngle(degrees: 8)
        let frontHip = PersonDepthAligner.AxisAngle(degrees: 12)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: frontShoulder, hipAngle: frontHip), .front)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 65), hipAngle: frontHip), .unverified)
        landmarks.removeValue(forKey: .leftEye); landmarks.removeValue(forKey: .rightEye)
        landmarks[.leftShoulder] = ScanPoint(x: 0.49, y: 0.35)
        landmarks[.rightShoulder] = ScanPoint(x: 0.51, y: 0.35)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 70), hipAngle: nil), .side)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: nil, hipAngle: nil), .unverified)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 70), hipAngle: PersonDepthAligner.AxisAngle(degrees: 25)), .unverified)
        landmarks[.leftEye] = ScanPoint(x: 0.45, y: 0.18); landmarks[.rightEye] = ScanPoint(x: 0.55, y: 0.18)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: landmarks, imageRotation: .up, shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 70), hipAngle: nil), .unverified)
    }
    func testEyesBelowShouldersDoNotEstablishFrontView() {
        let landmarks: [ScanJoint: ScanPoint] = [
            .nose: ScanPoint(x: 0.5, y: 0.2),
            .leftEye: ScanPoint(x: 0.46, y: 0.45), .rightEye: ScanPoint(x: 0.54, y: 0.45),
            .leftShoulder: ScanPoint(x: 0.4, y: 0.35), .rightShoulder: ScanPoint(x: 0.6, y: 0.35),
            .leftHip: ScanPoint(x: 0.43, y: 0.58), .rightHip: ScanPoint(x: 0.57, y: 0.58)
        ]
        XCTAssertEqual(PersonDepthAligner.estimateView(
            landmarks: landmarks,
            imageRotation: .up,
            shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 8),
            hipAngle: PersonDepthAligner.AxisAngle(degrees: 12)
        ), .unverified)
    }
    func testRotatedEyesBelowShouldersDoNotEstablishFrontView() {
        let landmarks: [ScanJoint: ScanPoint] = [
            .nose: ScanPoint(x: 0.2, y: 0.5),
            .leftEye: ScanPoint(x: 0.45, y: 0.54), .rightEye: ScanPoint(x: 0.45, y: 0.46),
            .leftShoulder: ScanPoint(x: 0.35, y: 0.4), .rightShoulder: ScanPoint(x: 0.35, y: 0.6),
            .leftHip: ScanPoint(x: 0.58, y: 0.43), .rightHip: ScanPoint(x: 0.58, y: 0.57)
        ]
        XCTAssertEqual(PersonDepthAligner.estimateView(
            landmarks: landmarks,
            imageRotation: .right,
            shoulderAngle: PersonDepthAligner.AxisAngle(degrees: 8),
            hipAngle: PersonDepthAligner.AxisAngle(degrees: 12)
        ), .unverified)
    }


    func testVerticalOnlyBilateralShoulderPointsDoNotEstablishFrontView() throws {
        var fixture = makeFixture()
        fixture.landmarks[.leftEye] = ScanPoint(x: 0.46, y: 0.18)
        fixture.landmarks[.rightEye] = ScanPoint(x: 0.54, y: 0.18)
        fixture.landmarks[.leftShoulder] = ScanPoint(x: 0.5, y: 0.35)
        fixture.landmarks[.rightShoulder] = ScanPoint(x: 0.5, y: 0.55)

        let result = try evaluate(fixture)
        XCTAssertNil(result.rejection)
        XCTAssertNil(result.shoulderAngle)
        XCTAssertEqual(PersonDepthAligner.estimateView(
            landmarks: fixture.landmarks,
            imageRotation: .up,
            shoulderAngle: result.shoulderAngle,
            hipAngle: result.hipAngle
        ), .unverified)
    }

    func testCalibratedAxisEvidenceSeparatesFrontSideAndContradiction() throws {
        var front = makeFixture()
        front.landmarks[.leftEye] = ScanPoint(x: 0.46, y: 0.18)
        front.landmarks[.rightEye] = ScanPoint(x: 0.54, y: 0.18)
        let frontResult = try evaluate(front)
        XCTAssertNil(frontResult.rejection)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: front.landmarks, imageRotation: .up, shoulderAngle: frontResult.shoulderAngle, hipAngle: frontResult.hipAngle), .front)

        var side = makeFixture()
        side.landmarks.removeValue(forKey: .leftEye); side.landmarks.removeValue(forKey: .rightEye)
        side.landmarks.removeValue(forKey: .rightHip)
        side.landmarks[.leftShoulder] = ScanPoint(x: 0.49, y: 0.35)
        side.landmarks[.rightShoulder] = ScanPoint(x: 0.51, y: 0.35)
        side.depth[22 * side.depthStride + 31] = 0.9
        side.depth[22 * side.depthStride + 32] = 2.4
        let sideResult = try evaluate(side)
        XCTAssertNil(sideResult.rejection)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: side.landmarks, imageRotation: .up, shoulderAngle: sideResult.shoulderAngle, hipAngle: sideResult.hipAngle), .side)

        var contradictory = side
        contradictory.landmarks[.rightHip] = ScanPoint(x: 0.58, y: 0.57)
        let conflict = try evaluate(contradictory)
        XCTAssertEqual(PersonDepthAligner.estimateView(landmarks: contradictory.landmarks, imageRotation: .up, shoulderAngle: conflict.shoulderAngle, hipAngle: conflict.hipAngle), .unverified)
    }

    func testPaddedRowsAndDifferingMaskResolutionAreHonored() throws {
        var f = makeFixture(width: 80, height: 80, depthWidth: 40, depthHeight: 40, depthStride: 44, byteStride: 44,
                            rect: (25, 10, 30, 60))
        let result = try evaluate(f)
        XCTAssertNil(result.rejection)
        XCTAssertEqual(result.representativeDepth ?? 0, 2, accuracy: 0.001)
        let smallerMask = makeFixture(width: 80, height: 80, depthWidth: 40, depthHeight: 40,
                                      maskWidth: 40, maskHeight: 40, rect: (12, 5, 16, 30))
        let scaled = try evaluate(smallerMask)
        XCTAssertNil(scaled.rejection)
        XCTAssertEqual(scaled.personCenter?.x ?? 0, result.personCenter?.x ?? -1, accuracy: 0.03)
        XCTAssertEqual(scaled.personHeight ?? 0, result.personHeight ?? -1, accuracy: 0.03)
        f.confidenceWidth = 39
        XCTAssertEqual(try evaluate(f).rejection, .invalidAlignment)
    }

    func testWrongAspectEmptyTinyAndEdgeClippedMasksReject() throws {
        var f = makeFixture()
        f.maskWidth = 48
        XCTAssertEqual(try evaluate(f).rejection, .invalidAlignment)
        f = makeFixture(maskValue: 0)
        XCTAssertEqual(try evaluate(f).rejection, .missingPerson)
        f = makeFixture(rect: (30, 28, 4, 8))
        XCTAssertEqual(try evaluate(f).rejection, .incompleteFraming)
        f = makeFixture(rect: (0, 10, 30, 45))
        XCTAssertEqual(try evaluate(f).rejection, .incompleteFraming)
    }
    func testRotatedHeadRegionMissingDepthIsRejected() throws {
        var f = makeFixture()
        f.rotation = .right
        f.mask = [UInt8](repeating: 0, count: 64 * 64)
        f.depth = [Float](repeating: 3, count: 64 * 64)
        for x in 8..<56 { for y in 20..<44 { f.mask[y * 64 + x] = 255; f.depth[y * 64 + x] = 2 } }
        f.landmarks = [
            .nose: ScanPoint(x: 0.23, y: 0.5), .leftShoulder: ScanPoint(x: 0.35, y: 0.62),
            .rightShoulder: ScanPoint(x: 0.35, y: 0.38), .leftHip: ScanPoint(x: 0.58, y: 0.58),
            .rightHip: ScanPoint(x: 0.58, y: 0.42), .leftAnkle: ScanPoint(x: 0.82, y: 0.56)
        ]
        for x in 8..<24 { for y in 20..<44 { f.depth[y * 64 + x] = .nan } }
        XCTAssertEqual(try evaluate(f).rejection, .insufficientPersonDepth)
    }

    func testOnePixelEdgeClipAndShortBackingStorageReject() throws {
        var f = makeFixture()
        f.mask[32 * 64] = 255
        XCTAssertEqual(try evaluate(f).rejection, .incompleteFraming)
        f = makeFixture()
        f.truncateDepthStorage = true
        XCTAssertEqual(try evaluate(f).rejection, .invalidAlignment)
    }

    func testLandmarksOutsidePersonAndMissingRegionalDepthReject() throws {
        var f = makeFixture()
        f.landmarks[.nose] = ScanPoint(x: 0.05, y: 0.05)
        XCTAssertEqual(try evaluate(f).rejection, .unreliablePose)
        f = makeFixture()
        for y in 12..<25 { for x in 20..<44 { f.depth[y * 64 + x] = .nan } }
        XCTAssertEqual(try evaluate(f).rejection, .insufficientPersonDepth)
    }

    func testNonfiniteDepthAndLowConfidenceDoNotCount() throws {
        for value: Float in [.nan, .infinity, 0, -1, 6] {
            var f = makeFixture()
            for y in 8..<56 { for x in 20..<44 { f.depth[y * 64 + x] = value } }
            XCTAssertEqual(try evaluate(f).rejection, .insufficientPersonDepth)
        }
        for level: UInt8 in [0, 3, 255] {
            var f = makeFixture()
            for y in 8..<56 { for x in 20..<44 { f.confidence[y * 64 + x] = level } }
            XCTAssertEqual(try evaluate(f).rejection, .insufficientPersonDepth)
        }
    }
    func testAnatomicalHeadToFootOrderingIsRequired() throws {
        var f = makeFixture()
        f.landmarks[.nose] = ScanPoint(x: 0.5, y: 0.65)
        XCTAssertEqual(try evaluate(f).rejection, .unreliablePose)
    }

    private struct Fixture {
        var imageWidth = 64, imageHeight = 64
        var depthWidth = 64, depthHeight = 64, depthStride = 64, byteStride = 64
        var maskWidth = 64, maskHeight = 64, maskStride = 64
        var confidenceWidth = 64
        var rotation: ScanImageRotation = .up
        var truncateDepthStorage = false
        var depth = [Float](repeating: 2, count: 64 * 64)
        var confidence = [UInt8](repeating: 2, count: 64 * 64)
        var mask = [UInt8](repeating: 0, count: 64 * 64)
        var landmarks: [ScanJoint: ScanPoint] = [
            .nose: ScanPoint(x: 0.5, y: 0.22), .leftShoulder: ScanPoint(x: 0.38, y: 0.34),
            .rightShoulder: ScanPoint(x: 0.62, y: 0.34), .leftHip: ScanPoint(x: 0.42, y: 0.57),
            .rightHip: ScanPoint(x: 0.58, y: 0.57), .leftAnkle: ScanPoint(x: 0.44, y: 0.82)
        ]
    }

    private func makeFixture(width: Int = 64, height: Int = 64, depthWidth: Int = 64, depthHeight: Int = 64,
                             depthStride: Int? = nil, byteStride: Int? = nil,
                             maskWidth: Int? = nil, maskHeight: Int? = nil,
                             rect: (Int, Int, Int, Int) = (20, 8, 24, 48), maskValue: UInt8 = 255) -> Fixture {
        var f = Fixture()
        f.imageWidth = width; f.imageHeight = height; f.depthWidth = depthWidth; f.depthHeight = depthHeight
        f.depthStride = depthStride ?? depthWidth; f.byteStride = byteStride ?? depthWidth
        f.confidenceWidth = depthWidth
        f.maskWidth = maskWidth ?? width; f.maskHeight = maskHeight ?? height; f.maskStride = f.maskWidth
        f.depth = [Float](repeating: 3, count: f.depthStride * depthHeight)
        f.confidence = [UInt8](repeating: 2, count: f.byteStride * depthHeight)
        f.mask = [UInt8](repeating: 0, count: f.maskStride * f.maskHeight)
        let (x, y, w, h) = rect
        if maskValue > 0 { for yy in max(0,y)..<min(f.maskHeight,y+h) { for xx in max(0,x)..<min(f.maskWidth,x+w) { f.mask[yy * f.maskStride + xx] = maskValue } } }
        for yy in 0..<depthHeight { for xx in 0..<depthWidth {
            let mx = min(f.maskWidth - 1, Int((Double(xx) + 0.5) * Double(f.maskWidth) / Double(depthWidth)))
            let my = min(f.maskHeight - 1, Int((Double(yy) + 0.5) * Double(f.maskHeight) / Double(depthHeight)))
            if f.mask[my * f.maskStride + mx] >= 128 { f.depth[yy * f.depthStride + xx] = 2 }
        } }
        f.landmarks = [
            .nose: ScanPoint(x: 0.5, y: 0.23), .leftShoulder: ScanPoint(x: 0.38, y: 0.35),
            .rightShoulder: ScanPoint(x: 0.62, y: 0.35), .leftHip: ScanPoint(x: 0.42, y: 0.58),
            .rightHip: ScanPoint(x: 0.58, y: 0.58), .leftAnkle: ScanPoint(x: 0.44, y: 0.82)
        ]
        return f
    }

    private func evaluate(_ f: Fixture) throws -> PersonDepthAligner.Result {
        return f.depth.withUnsafeBytes { db in f.confidence.withUnsafeBytes { cb in f.mask.withUnsafeBytes { mb in
            let storedDepth = f.truncateDepthStorage
                ? UnsafeRawBufferPointer(rebasing: db[..<(db.count - 1)]) : db
            let depth = ScanDepthPlane(bytes: storedDepth, width: f.depthWidth, height: f.depthHeight, bytesPerRow: f.depthStride * 4)
            let confidence = ScanBytePlane(bytes: cb, width: f.confidenceWidth, height: f.depthHeight, bytesPerRow: f.byteStride)
            let mask = ScanBytePlane(bytes: mb, width: f.maskWidth, height: f.maskHeight, bytesPerRow: f.maskStride)
            let metadata = ScanFrameMetadata(timestamp: 1, imageSize: ScanImageSize(width: f.imageWidth, height: f.imageHeight), depthSize: ScanImageSize(width: f.depthWidth, height: f.depthHeight), maskSize: ScanImageSize(width: f.maskWidth, height: f.maskHeight), imageRotation: f.rotation, maskRotation: .up, calibration: ScanCameraCalibration(fx: 50, fy: 50, cx: 32, cy: 32), landmarks: f.landmarks, cameraPosition: ScanVector(x: 0,y: 0,z: 0), cameraForward: ScanVector(x: 0,y: 0,z: -1))
            return PersonDepthAligner.evaluate(depth: depth, confidence: confidence, mask: mask, metadata: metadata)
        } } }
    }
}
#endif
