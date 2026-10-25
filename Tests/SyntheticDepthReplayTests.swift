#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

final class SyntheticDepthReplayTests: XCTestCase {
    func testReviewedRayCastIsDeterministicForOneIdentity() throws {
        let first = try SyntheticDepthReplayFactory.make(.columnA)
        let second = try SyntheticDepthReplayFactory.make(.columnA)
        XCTAssertEqual(first.frames, second.frames)
    }

    func testRayCastProducesCentralDepthAndBackgroundWithConsistentConfidenceMask() throws {
        let replay = try SyntheticDepthReplayFactory.make(.columnA)
        let frame = try XCTUnwrap(replay.frames.first)
        let depth = try XCTUnwrap(frame.depth)
        let confidence = try XCTUnwrap(frame.confidence)
        let mask = try XCTUnwrap(frame.mask)
        var hit: Float?
        var background: (Int, Int)?
        for y in 0..<depth.height {
            for x in 0..<depth.width {
                let value = try Self.depth(depth, x: x, y: y)
                if maskByte(mask, x: x, y: y) >= 128 {
                    XCTAssertEqual(confidenceByte(confidence, x: x, y: y), 2)
                    if x == 63 || x == 64, y == 47 || y == 48 { hit = value }
                } else {
                    XCTAssertEqual(value, 0)
                    XCTAssertEqual(confidenceByte(confidence, x: x, y: y), 0)
                    XCTAssertEqual(maskByte(mask, x: x, y: y), 0)
                    background = background ?? (x, y)
                }
            }
        }
        let centerDepth = try XCTUnwrap(hit)
        // Nearest front surface is 2 - 0.12 m, not the far intersection.
        // Half-pixel lateral offset adds ~0.000123 m at this raster resolution.
        XCTAssertEqual(centerDepth, 2.0 - 0.12, accuracy: 0.0002)
        XCTAssertNotNil(background)
        let (bx, by) = try XCTUnwrap(background)
        XCTAssertEqual(try Self.depth(depth, x: bx, y: by), 0)
        XCTAssertEqual(confidenceByte(confidence, x: bx, y: by), 0)
        XCTAssertEqual(maskByte(mask, x: bx, y: by), 0)
    }

    func testReferenceParametersChangeRenderedEvidence() throws {
        let a = try SyntheticDepthReplayFactory.make(.columnA)
        let b = try SyntheticDepthReplayFactory.make(.columnB)
        XCTAssertNotEqual(SyntheticDepthReplayFactory.reference(for: .columnA),
                          SyntheticDepthReplayFactory.reference(for: .columnB))
        XCTAssertNotEqual(a.frames[0].depth, b.frames[0].depth)
        XCTAssertNotEqual(a.frames[1].depth, b.frames[1].depth)
        XCTAssertNotEqual(a.frames[0].mask, b.frames[0].mask)
    }

    func testRayDistanceRasterStoresEuclideanRangeRatherThanOpticalZ() throws {
        let optical = try SyntheticDepthReplayFactory.make(.columnA).frames[0]
        let range = try SyntheticDepthReplayFactory.make(.rayDistanceA).frames[0]
        XCTAssertEqual(optical.depthSemantics, .opticalAxis)
        XCTAssertEqual(range.depthSemantics, .euclideanRayDistance)
        let od = try XCTUnwrap(optical.depth), rd = try XCTUnwrap(range.depth)
        let opticalMask = try XCTUnwrap(optical.mask)
        var foundOffAxisDifference = false
        for y in 0..<od.height {
            for x in 0..<od.width where maskByte(opticalMask, x: x, y: y) >= 128 {
                let z = try Self.depth(od, x: x, y: y)
                let distance = try Self.depth(rd, x: x, y: y)
                XCTAssertGreaterThanOrEqual(distance + 1e-6, z)
                if distance > z + 0.0001 { foundOffAxisDifference = true }
            }
        }
        XCTAssertTrue(foundOffAxisDifference)
    }

    func testMovedCameraChangesKnownExtrinsicsAndRasterEvidence() throws {
        let base = try SyntheticDepthReplayFactory.make(.columnA)
        let moved = try SyntheticDepthReplayFactory.make(.movedCameraA)
        XCTAssertNotEqual(base.frames[0].pose, moved.frames[0].pose)
        XCTAssertNotEqual(base.frames[1].pose, moved.frames[1].pose)
        XCTAssertNotEqual(base.frames[0].depth, moved.frames[0].depth)
        XCTAssertEqual(moved.frames.map(\.view), [.front, .side])
        for frame in moved.frames {
            let pose = frame.pose
            XCTAssertNotEqual(pose.forward, base.frames[frame.view == .front ? 0 : 1].pose.forward)
            let cross = SIMD3<Double>(
                pose.right.y * pose.down.z - pose.right.z * pose.down.y,
                pose.right.z * pose.down.x - pose.right.x * pose.down.z,
                pose.right.x * pose.down.y - pose.right.y * pose.down.x
            )
            XCTAssertEqual(cross.x, pose.forward.x, accuracy: 1e-12)
            XCTAssertEqual(cross.y, pose.forward.y, accuracy: 1e-12)
            XCTAssertEqual(cross.z, pose.forward.z, accuracy: 1e-12)
        }
    }


    func testDifferentCalibrationUsesNonSquareRasterAndIndependentFocalLengths() throws {
        let frame = try XCTUnwrap(SyntheticDepthReplayFactory.make(.changedCalibrationA).frames.first)
        XCTAssertEqual(frame.calibration.imageWidth, 640)
        XCTAssertEqual(frame.calibration.imageHeight, 480)
        XCTAssertNotEqual(frame.calibration.fx, frame.calibration.fy)
        XCTAssertEqual(frame.depth?.width, 160)
        XCTAssertEqual(frame.depth?.height, 120)
        XCTAssertEqual(frame.depth?.bytesPerRow, 656)
    }

    func testRotatedRasterRotatesAllObservationPlanesAndKeepsTruth() throws {
        let native = try XCTUnwrap(SyntheticDepthReplayFactory.make(.columnA).frames.first)
        let rotated = try XCTUnwrap(SyntheticDepthReplayFactory.make(.rotatedRasterA).frames.first)
        XCTAssertEqual(rotated.rotation, .right)
        XCTAssertEqual(rotated.maskRotation, .right)
        XCTAssertEqual(rotated.depth?.width, 96)
        XCTAssertEqual(rotated.depth?.height, 128)
        XCTAssertEqual(rotated.depth?.bytesPerRow, 400)
        XCTAssertEqual(rotated.mask?.bytesPerRow, 104)
        let nativeDepth = try XCTUnwrap(native.depth), rotatedDepth = try XCTUnwrap(rotated.depth)
        let nativeMask = try XCTUnwrap(native.mask), rotatedMask = try XCTUnwrap(rotated.mask)
        let nativeConfidence = try XCTUnwrap(native.confidence), rotatedConfidence = try XCTUnwrap(rotated.confidence)
        for y in 0..<nativeDepth.height {
            for x in 0..<nativeDepth.width {
                let storedX = nativeDepth.height - 1 - y, storedY = x
                XCTAssertEqual(try Self.depth(nativeDepth, x: x, y: y),
                               try Self.depth(rotatedDepth, x: storedX, y: storedY), accuracy: 0.00001)
                XCTAssertEqual(maskByte(nativeMask, x: x, y: y), maskByte(rotatedMask, x: storedX, y: storedY))
                XCTAssertEqual(confidenceByte(nativeConfidence, x: x, y: y), confidenceByte(rotatedConfidence, x: storedX, y: storedY))
            }
        }
    }

    func testSDKPixelCenterIntrinsicsConvertToSamePhysicalRays() throws {
        let corner = try XCTUnwrap(SyntheticDepthReplayFactory.make(.columnA).frames.first)
        let sdk = try XCTUnwrap(SyntheticDepthReplayFactory.make(.sdkPixelOriginA).frames.first)
        XCTAssertEqual(sdk.calibration.origin, .upperLeftPixelCenter)
        XCTAssertEqual(corner.calibration.origin, .rasterCorner)
        XCTAssertEqual(corner.calibration.cx - sdk.calibration.cx, 0.5, accuracy: 0.000001)
        XCTAssertEqual(corner.calibration.cy - sdk.calibration.cy, 0.5, accuracy: 0.000001)
        let a = try XCTUnwrap(corner.depth), b = try XCTUnwrap(sdk.depth)
        for y in 0..<a.height {
            for x in 0..<a.width {
                XCTAssertEqual(try Self.depth(a, x: x, y: y), try Self.depth(b, x: x, y: y), accuracy: 0.00001)
            }
        }
    }

    func testPaddedRasterRowsHaveZeroPaddingAndExactBackingLength() throws {
        let replay = try SyntheticDepthReplayFactory.make(.columnA)
        for frame in replay.frames {
            for raster in [frame.depth, frame.confidence, frame.mask].compactMap({ $0 }) {
                let bytesPerPixel = raster.bytesPerRow == frame.depth?.bytesPerRow ? 4 : 1
                XCTAssertGreaterThan(raster.bytesPerRow, raster.width * bytesPerPixel)
                XCTAssertEqual(raster.bytes.count, raster.bytesPerRow * raster.height)
                for y in 0..<raster.height {
                    let paddingStart = y * raster.bytesPerRow + raster.width * bytesPerPixel
                    let paddingEnd = (y + 1) * raster.bytesPerRow
                    XCTAssertTrue(raster.bytes[paddingStart..<paddingEnd].allSatisfy { $0 == 0 })
                }
            }
        }
    }

    func testPartialOcclusionRemovesDepthConfidenceAndMaskOnlyInsideItsRegion() throws {
        let complete = try SyntheticDepthReplayFactory.make(.columnA)
        let partial = try SyntheticDepthReplayFactory.make(.partialOcclusionA)
        // Independently projected interior rays near world Y=0.96. Front X≈0.10,
        // side Z≈-0.06; all lie inside the authored cutout. The Y≈1.13 rays
        // below lie outside it. Different resolutions must not be compared by
        // global mask counts: silhouette quantization changes those counts.
        for (index, fullX, partialX) in [(0, 69, 104), (1, 67, 101)] {
            let fullMask = try XCTUnwrap(complete.frames[index].mask)
            let mask = try XCTUnwrap(partial.frames[index].mask)
            let confidence = try XCTUnwrap(partial.frames[index].confidence)
            let depth = try XCTUnwrap(partial.frames[index].depth)
            XCTAssertGreaterThanOrEqual(maskByte(fullMask, x: fullX, y: 44), 128)
            XCTAssertEqual(maskByte(mask, x: partialX, y: 66), 0)
            XCTAssertEqual(confidenceByte(confidence, x: partialX, y: 66), 0)
            XCTAssertEqual(try Self.depth(depth, x: partialX, y: 66), 0)
            XCTAssertGreaterThanOrEqual(maskByte(mask, x: partialX, y: 50), 128)
            XCTAssertEqual(confidenceByte(confidence, x: partialX, y: 50), 2)
            XCTAssertGreaterThan(try Self.depth(depth, x: partialX, y: 50), 0.1)
        }
    }

    func testEveryReplayIDProducesBoundedOwnedRasterFrames() throws {
        for id in ReplayID.allCases {
            let replay = try SyntheticDepthReplayFactory.make(id)
            XCTAssertEqual(replay.id, id)
            XCTAssertEqual(replay.frames.count, 2)
            for frame in replay.frames {
                for raster in [frame.depth, frame.confidence, frame.mask].compactMap({ $0 }) {
                    XCTAssertGreaterThan(raster.width, 0)
                    XCTAssertGreaterThan(raster.height, 0)
                    XCTAssertLessThanOrEqual(raster.width, ReplayLimits.maximumRasterDimension)
                    XCTAssertLessThanOrEqual(raster.height, ReplayLimits.maximumRasterDimension)
                    XCTAssertLessThanOrEqual(raster.bytes.count, ReplayLimits.maximumRasterBytes)
                }
            }
        }
    }

    func testNegativeReplayCasesMutateObservationOrAdmissionMetadata() throws {
        let valid = try SyntheticDepthReplayFactory.make(.columnA)
        let missingDepth = try SyntheticDepthReplayFactory.make(.missingDepth)
        XCTAssertNil(missingDepth.frames[0].depth)
        let badCalibration = try SyntheticDepthReplayFactory.make(.badCalibration)
        XCTAssertEqual(badCalibration.frames[0].calibration.fx, 0)
        let conflicting = try SyntheticDepthReplayFactory.make(.conflictingViews)
        XCTAssertNotEqual(conflicting.frames[1].depth, valid.frames[1].depth)
        let inconsistent = try SyntheticDepthReplayFactory.make(.inconsistentPose)
        XCTAssertNotEqual(inconsistent.frames[1].pose, valid.frames[1].pose)
        let missingMask = try SyntheticDepthReplayFactory.make(.missingMask)
        XCTAssertNil(missingMask.frames[0].mask)
        let misaligned = try SyntheticDepthReplayFactory.make(.misalignedMask)
        XCTAssertNotEqual(misaligned.frames[0].maskRotation, misaligned.frames[0].rotation)
        let lowConfidence = try SyntheticDepthReplayFactory.make(.lowConfidence)
        let confidence = try XCTUnwrap(lowConfidence.frames[0].confidence)
        XCTAssertTrue((0..<confidence.height).allSatisfy { y in
            (0..<confidence.width).allSatisfy { x in confidenceByte(confidence, x: x, y: y) == 0 }
        })
        let duplicate = try SyntheticDepthReplayFactory.make(.duplicateFrame)
        XCTAssertEqual(duplicate.frames[0].frameID, duplicate.frames[1].frameID)
        XCTAssertEqual(duplicate.frames[0].sequence, duplicate.frames[1].sequence)
        let stale = try SyntheticDepthReplayFactory.make(.staleFrame)
        XCTAssertGreaterThan(stale.evaluationTimestamp - stale.frames[0].timestamp, ReplayLimits.maximumFrameAge)
        let unverified = try SyntheticDepthReplayFactory.make(.unverifiedSource)
        XCTAssertEqual(unverified.frames[0].source, .unverifiedLiveSensor)
    }

    func testCancellationIsCheckedBeforeAndDuringRasterGeneration() {
        XCTAssertThrowsError(try SyntheticDepthReplayFactory.make(.columnA, cancellationCheck: { true })) {
            XCTAssertEqual($0 as? ReplayFailure, .cancelled)
        }
        var checks = 0
        XCTAssertThrowsError(try SyntheticDepthReplayFactory.make(.columnA, cancellationCheck: {
            checks += 1
            return checks > 4
        })) {
            XCTAssertEqual($0 as? ReplayFailure, .cancelled)
        }
    }

    private static func depth(_ raster: ReplayRaster, x: Int, y: Int) throws -> Float {
        guard x >= 0, y >= 0, x < raster.width, y < raster.height,
              raster.bytesPerRow >= raster.width * 4,
              raster.bytes.count == raster.bytesPerRow * raster.height else {
            throw ReplayFailure.invalidLayout
        }
        let offset = y * raster.bytesPerRow + x * 4
        let bits = UInt32(raster.bytes[offset])
            | UInt32(raster.bytes[offset + 1]) << 8
            | UInt32(raster.bytes[offset + 2]) << 16
            | UInt32(raster.bytes[offset + 3]) << 24
        return Float(bitPattern: bits)
    }

    private func confidenceByte(_ raster: ReplayRaster, x: Int, y: Int) -> UInt8 {
        raster.bytes[y * raster.bytesPerRow + x]
    }

    private func maskByte(_ raster: ReplayRaster, x: Int, y: Int) -> UInt8 {
        raster.bytes[y * raster.bytesPerRow + x]
    }
}
#endif
