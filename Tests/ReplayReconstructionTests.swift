#if DEBUG
import XCTest
@testable import FitCheck

final class ReplayReconstructionTests: XCTestCase {
    func testAAndBProduceDifferentObservationDerivedPointsSectionsAndMeshes() throws {
        let aReplay = try SyntheticDepthReplayFactory.make(.columnA)
        let bReplay = try SyntheticDepthReplayFactory.make(.columnB)
        let aAnalysis = try ReplaySpatialMapper.analyze(frames: aReplay.frames, evaluationTimestamp: aReplay.evaluationTimestamp)
        let bAnalysis = try ReplaySpatialMapper.analyze(frames: bReplay.frames, evaluationTimestamp: bReplay.evaluationTimestamp)
        let a = try ReplayReconstructionEngine.reconstruct(aReplay), b = try ReplayReconstructionEngine.reconstruct(bReplay)
        XCTAssertNoThrow(try a.validate()); XCTAssertNoThrow(try b.validate())
        XCTAssertEqual(a.sections.count, 6)
        XCTAssertEqual(a.mesh.vertices.count, 6 * a.supportedAngularIndices.count)
        let edgesPerRing = a.supportedAngularIndices.count - (a.supportedAngularIndices.count == ReplayLimits.radialSegments ? 0 : 1)
        XCTAssertEqual(a.mesh.indices.count, 5 * edgesPerRing * 6)
        XCTAssertLessThan(a.supportedAngularIndices.count, ReplayLimits.radialSegments, "Unsupported angular regions remain unmodeled")
        for triangle in stride(from: 0, to: a.mesh.indices.count, by: 3) {
            let slots = [Int(a.mesh.indices[triangle]) % a.supportedAngularIndices.count,
                         Int(a.mesh.indices[triangle + 1]) % a.supportedAngularIndices.count,
                         Int(a.mesh.indices[triangle + 2]) % a.supportedAngularIndices.count]
            XCTAssertLessThanOrEqual((slots.max() ?? 0) - (slots.min() ?? 0), 1,
                                     "No triangle crosses an unsupported angular gap")
        }
        XCTAssertTrue(a.sections.allSatisfy { section in
            a.supportedAngularIndices.allSatisfy { section.angularSupportMask & (UInt32(1) << UInt32($0)) != 0 }
        })
        XCTAssertNotEqual(aAnalysis.views.map(\.points), bAnalysis.views.map(\.points))
        XCTAssertNotEqual(a.sections, b.sections)
        XCTAssertNotEqual(a.mesh.vertices.map(\.position), b.mesh.vertices.map(\.position))
        XCTAssertEqual(a.capability, .neutralSyntheticIllustrationV1)
        XCTAssertEqual(a.provenance, .reviewedFirstPartyDepthReplay)
        XCTAssertEqual(a.stages, [.framesValidated, .pointsMapped, .viewsRegistered, .sectionsExtracted, .meshGenerated])
        XCTAssertEqual(a.mappingSummaries.count, 2)
        XCTAssertTrue(a.mappingSummaries.allSatisfy { $0.counts.accepted > 0 })
    }

    func testRadiiBoundsMatchIndependentAnalyticReferenceWithinTolerance() throws {
        let a = try reconstruct(.columnA), b = try reconstruct(.columnB)
        // Independently authored test expectations; no reconstruction data supplies these values.
        for section in a.sections {
            XCTAssertEqual(section.halfWidth, 0.20, accuracy: 0.003)
            XCTAssertEqual(section.halfDepth, 0.12, accuracy: 0.003)
        }
        for section in b.sections {
            XCTAssertEqual(section.halfWidth, 0.14, accuracy: 0.003)
            XCTAssertEqual(section.halfDepth, 0.20, accuracy: 0.003)
        }
        XCTAssertLessThanOrEqual(a.mesh.minimum.x, a.mesh.maximum.x)
        XCTAssertLessThanOrEqual(a.mesh.minimum.z, a.mesh.maximum.z)
        XCTAssertTrue(a.mesh.vertices.allSatisfy {
            abs(Double($0.position.x)) <= 0.203 && abs(Double($0.position.z)) <= 0.123
        })
        XCTAssertEqual(a.mesh.minimum.y, 0.45, accuracy: 0.0001)
        XCTAssertEqual(a.mesh.maximum.y, 1.30, accuracy: 0.0001)
    }

    func testMovedChangedCalibrationRotatedRasterRayDistanceAndPixelOriginAreInvariant() throws {
        let base = try reconstruct(.columnA)
        for id in [ReplayID.movedCameraA, .changedCalibrationA, .rotatedRasterA, .rayDistanceA, .sdkPixelOriginA, .anisotropicRasterA] {
            let replay = try SyntheticDepthReplayFactory.make(id)
            let result = try ReplayReconstructionEngine.reconstruct(replay)
            let commonAngles = result.supportedAngularIndices.filter { base.supportedAngularIndices.contains($0) }
            XCTAssertGreaterThanOrEqual(commonAngles.count, ReplayLimits.minimumSupportedAngularVertices, "\(id)")
            for ring in result.sections.indices {
                for angle in commonAngles {
                    guard let actualSlot = result.supportedAngularIndices.firstIndex(of: angle),
                          let expectedSlot = base.supportedAngularIndices.firstIndex(of: angle) else { continue }
                    let actual = result.mesh.vertices[ring * result.supportedAngularIndices.count + actualSlot].position
                    let expected = base.mesh.vertices[ring * base.supportedAngularIndices.count + expectedSlot].position
                    XCTAssertEqual(actual.x, expected.x, accuracy: 0.003, "\(id)")
                    XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, "\(id)")
                    XCTAssertEqual(actual.z, expected.z, accuracy: 0.003, "\(id)")
                }
            }
            for (actual, expected) in zip(result.sections, base.sections) {
                XCTAssertEqual(actual.halfWidth, expected.halfWidth, accuracy: 0.003, "\(id)")
                XCTAssertEqual(actual.halfDepth, expected.halfDepth, accuracy: 0.003, "\(id)")
            }
        }
    }

    func testMaskCoordinatesNormalizeAcrossDifferentRegisteredRasterSize() throws {
        var frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        for frameIndex in frames.indices {
            let original = try XCTUnwrap(frames[frameIndex].mask)
            var resized = Data(count: 64 * 48)
            for y in 0..<48 {
                for x in 0..<64 {
                    let sourceX = min(original.width - 1, Int((Double(x) + 0.5) / 64 * Double(original.width)))
                    let sourceY = min(original.height - 1, Int((Double(y) + 0.5) / 48 * Double(original.height)))
                    resized[y * 64 + x] = original.bytes[sourceY * original.bytesPerRow + sourceX]
                }
            }
            frames[frameIndex].mask = ReplayRaster(width: 64, height: 48, bytesPerRow: 64, bytes: resized)
        }
        let analysis = try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)
        XCTAssertEqual(analysis.sections.count, ReplayLimits.sectionHeights.count)
        for section in analysis.sections {
            XCTAssertEqual(section.halfWidth, 0.20, accuracy: 0.003)
            XCTAssertEqual(section.halfDepth, 0.12, accuracy: 0.003)
        }
    }

    func testMaskThresholdIsInclusiveAt128() throws {
        var frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        for frameIndex in frames.indices {
            var raster = try XCTUnwrap(frames[frameIndex].mask)
            var bytes = raster.bytes
            for y in 0..<raster.height {
                for x in 0..<raster.width {
                    bytes[y * raster.bytesPerRow + x] = 128
                }
            }
            raster.bytes = bytes
            frames[frameIndex].mask = raster
        }
        XCTAssertNoThrow(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25))
        for frameIndex in frames.indices {
            var raster = try XCTUnwrap(frames[frameIndex].mask)
            var bytes = raster.bytes
            for y in 0..<raster.height {
                for x in 0..<raster.width {
                    bytes[y * raster.bytesPerRow + x] = 127
                }
            }
            raster.bytes = bytes
            frames[frameIndex].mask = raster
        }
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .insufficientCoverage)
        }
    }

    func testEligibleNonfiniteDepthFailsClosed() throws {
        var frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        var depth = try XCTUnwrap(frames[0].depth)
        let mask = try XCTUnwrap(frames[0].mask)
        let confidence = try XCTUnwrap(frames[0].confidence)
        var bytes = depth.bytes
        var corrupted = false
        for y in 0..<depth.height where !corrupted {
            for x in 0..<depth.width where mask.bytes[y * mask.bytesPerRow + x] >= 128 &&
                confidence.bytes[y * confidence.bytesPerRow + x] == 2 {
                let offset = y * depth.bytesPerRow + x * 4
                let bits = Float.nan.bitPattern.littleEndian
                bytes[offset] = UInt8(truncatingIfNeeded: bits)
                bytes[offset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
                bytes[offset + 2] = UInt8(truncatingIfNeeded: bits >> 16)
                bytes[offset + 3] = UInt8(truncatingIfNeeded: bits >> 24)
                corrupted = true
                break
            }
        }
        XCTAssertTrue(corrupted)
        depth.bytes = bytes
        frames[0].depth = depth
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .invalidDepth)
        }
    }

    func testPartialOcclusionSucceedsOnlyWithIndependentSupportInEveryBand() throws {
        let result = try reconstruct(.partialOcclusionA)
        XCTAssertNoThrow(try result.validate())
        XCTAssertTrue(result.sections.allSatisfy {
            $0.frontSamples >= ReplayLimits.minimumPointsPerSectionView &&
            $0.sideSamples >= ReplayLimits.minimumPointsPerSectionView
        })
        XCTAssertEqual(result.sections.map(\.height), ReplayLimits.sectionHeights)
    }

    func testMissingConflictingInvalidDuplicateStaleAndUnverifiedReplaysReject() throws {
        for (id, expected) in [
            (ReplayID.missingDepth, ReplayFailure.missingDepth),
            (.badCalibration, .invalidCalibration),
            (.conflictingViews, .conflictingViews),
            (.inconsistentPose, .conflictingViews),
            (.missingMask, .missingMask),
            (.misalignedMask, .maskAlignment),
            (.lowConfidence, .insufficientCoverage),
            (.duplicateFrame, .duplicateFrame),
            (.staleFrame, .staleFrame),
            (.unverifiedSource, .unverifiedSource),
            (.occlusionGap, .insufficientCoverage)
        ] {
            XCTAssertThrowsError(try reconstruct(id), "\(id)") { XCTAssertEqual($0 as? ReplayFailure, expected, "\(id)") }
        }
    }

    func testMapperRejectsUnsupportedEvidenceBeforeReturningPoints() throws {
        var frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        frames[0].units = .centimetres
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .unsupportedUnits)
        }
        frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        frames[0].pose.direction = .worldToOptical
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .invalidPose)
        }
        frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        frames[0].rotation = .unsupported
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .unsupportedRotation)
        }
        frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        var depth = try XCTUnwrap(frames[0].depth)
        depth.bytesPerRow = Int.max
        frames[0].depth = depth
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .invalidLayout)
        }
    }

    func testCancellationIsObservedDuringBoundedRasterMapping() throws {
        let replay = try SyntheticDepthReplayFactory.make(.columnA)
        var checks = 0
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: replay.frames, evaluationTimestamp: replay.evaluationTimestamp) {
            checks += 1
            return checks >= 4
        }) { XCTAssertEqual($0 as? ReplayFailure, .cancelled) }
        XCTAssertEqual(checks, 4)
    }

    func testFiniteWrongCalibrationAndEssentialMissingBandCannotUseHiddenReference() throws {
        var frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        frames[0].calibration.fx *= 1.2
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .conflictingViews)
        }
        frames = try SyntheticDepthReplayFactory.make(.columnA).frames
        let depth = try XCTUnwrap(frames[0].depth)
        var mask = try XCTUnwrap(frames[0].mask)
        for y in 0..<depth.height {
            for x in 0..<depth.width where mask.bytes[y * mask.bytesPerRow + x] >= 128 {
                let i = y * depth.bytesPerRow + x * 4
                let bits = UInt32(depth.bytes[i]) | UInt32(depth.bytes[i+1]) << 8 | UInt32(depth.bytes[i+2]) << 16 | UInt32(depth.bytes[i+3]) << 24
                let z = Double(Float(bitPattern: bits))
                let worldY = 0.9 - (((Double(y) + 0.5) / 96 * 240 - 120) / 290 * z)
                if abs(worldY - 0.79) < 0.04 { mask.bytes[y * mask.bytesPerRow + x] = 0 }
            }
        }
        frames[0].mask = mask
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .insufficientCoverage)
        }
    }

    func testRegistrationRejectsCoincidentCamerasNegativeTimeAndOverLimitFrames() throws {
        let source = try SyntheticDepthReplayFactory.make(.columnA).frames
        var frames = source
        frames[1].pose.translation = frames[0].pose.translation
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .invalidPose)
        }
        frames = source
        frames[0].timestamp = -1
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .staleFrame)
        }
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: source + [source[0]], evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .resourceLimit)
        }
        frames = source
        frames[0].depth?.width = Int.max
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .resourceLimit)
        }
        frames = source
        frames[0].pose.translation.x = Double.greatestFiniteMagnitude
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: frames, evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .invalidPose)
        }
    }

    func testMatchingShapeDoesNotAuthorizeMixingDifferentSyntheticCaptures() throws {
        let first = try SyntheticDepthReplayFactory.make(.columnA)
        let other = try SyntheticDepthReplayFactory.make(.movedCameraA)
        XCTAssertThrowsError(try ReplaySpatialMapper.analyze(frames: [first.frames[0], other.frames[1]], evaluationTimestamp: 10.25)) {
            XCTAssertEqual($0 as? ReplayFailure, .inconsistentCapture)
        }
    }

    private func reconstruct(_ id: ReplayID) throws -> ReplayGeometryResult {
        try ReplayReconstructionEngine.reconstruct(SyntheticDepthReplayFactory.make(id))
    }
}
#endif
