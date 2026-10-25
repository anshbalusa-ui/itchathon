#if DEBUG
import Foundation

/// Converts only bounded, reviewed, calibrated replay rasters into common-world observations.
enum ReplaySpatialMapper {
    static func analyze(frames: [ReplayFrame], evaluationTimestamp: Double,
                        cancellationCheck: () -> Bool = { Task.isCancelled }) throws -> ReplayAnalysis {
        try check(cancellationCheck)
        guard frames.count <= ReplayLimits.maximumFrames else { throw ReplayFailure.resourceLimit }
        guard frames.count == 2 else { throw ReplayFailure.duplicateFrame }
        guard evaluationTimestamp.isFinite, evaluationTimestamp >= 0 else { throw ReplayFailure.staleFrame }
        let ordered = frames.sorted { $0.sequence < $1.sequence }
        let front = ordered[0], side = ordered[1]
        guard front.view == .front, side.view == .side else { throw ReplayFailure.duplicateFrame }
        guard front.sequence > 0, side.sequence > 0,
              front.sequence != side.sequence, front.frameID != side.frameID else { throw ReplayFailure.duplicateFrame }
        guard !front.frameID.isEmpty, front.frameID.utf8.count <= 64,
              !side.frameID.isEmpty, side.frameID.utf8.count <= 64,
              !front.captureID.isEmpty, front.captureID.utf8.count <= 128,
              front.captureID == side.captureID, front.subject == side.subject,
              front.subject == "fictional-geometric-object", front.schemaVersion == ReplayLimits.schemaVersion,
              side.schemaVersion == ReplayLimits.schemaVersion else { throw ReplayFailure.inconsistentCapture }
        guard front.source == .reviewedSimulation, side.source == .reviewedSimulation else { throw ReplayFailure.unverifiedSource }
        guard front.timestamp.isFinite, side.timestamp.isFinite, front.timestamp >= 0,
              side.timestamp >= 0, front.timestamp < side.timestamp,
              evaluationTimestamp >= side.timestamp, evaluationTimestamp - front.timestamp <= ReplayLimits.maximumFrameAge,
              side.timestamp - front.timestamp <= ReplayLimits.maximumPairInterval else { throw ReplayFailure.staleFrame }
        guard front.units == .metres, side.units == .metres, front.metresPerUnit == 1, side.metresPerUnit == 1 else { throw ReplayFailure.unsupportedUnits }
        guard front.pixelConvention == .topLeftCenters, side.pixelConvention == .topLeftCenters,
              front.registration == .sharedFieldOfViewPixelCenters, side.registration == .sharedFieldOfViewPixelCenters,
              front.depthEncoding == .float32LittleEndian, side.depthEncoding == .float32LittleEndian else { throw ReplayFailure.unsupportedConvention }
        guard front.pose.referenceFrame == side.pose.referenceFrame else { throw ReplayFailure.inconsistentCapture }
        try ReplayCameraMath.validate(front.pose); try ReplayCameraMath.validate(side.pose)
        let verticalAgreement = dot(front.pose.down, side.pose.down)
        let viewpointSeparation = abs(dot(front.pose.forward, side.pose.forward))
        guard verticalAgreement >= 0.99, viewpointSeparation <= 0.25,
              abs(front.pose.forward.y) <= 0.05, abs(side.pose.forward.y) <= 0.05 else { throw ReplayFailure.invalidPose }
        let displacement = side.pose.translation - front.pose.translation
        guard dot(displacement, displacement) >= ReplayLimits.minimumCameraBaseline * ReplayLimits.minimumCameraBaseline,
              -front.pose.down.y >= 0.99, -side.pose.down.y >= 0.99 else { throw ReplayFailure.invalidPose }
        var totalRasterBytes = 0, totalSamples = 0
        for frame in ordered {
            for raster in [frame.depth, frame.confidence, frame.mask].compactMap({ $0 }) {
                let (sum, overflow) = totalRasterBytes.addingReportingOverflow(raster.bytes.count)
                guard !overflow, sum <= ReplayLimits.maximumRasterBytes else { throw ReplayFailure.resourceLimit }
                totalRasterBytes = sum
            }
            if let depth = frame.depth {
                let (samples, sampleOverflow) = depth.width.multipliedReportingOverflow(by: depth.height)
                let (total, totalOverflow) = totalSamples.addingReportingOverflow(samples)
                guard depth.width > 0, depth.height > 0, !sampleOverflow, !totalOverflow,
                      samples <= ReplayLimits.maximumRasterSamples, total <= ReplayLimits.maximumPoints else {
                    throw ReplayFailure.resourceLimit
                }
                totalSamples = total
            }
        }
        let (pointBytes, pointByteOverflow) = totalSamples.multipliedReportingOverflow(by: MemoryLayout<SIMD3<Double>>.stride)
        let (workingPointBytes, workingOverflow) = pointBytes.multipliedReportingOverflow(by: 2)
        let (partialBytes, rasterAndPointOverflow) = totalRasterBytes.addingReportingOverflow(workingPointBytes)
        let (logicalBytes, meshOverflow) = partialBytes.addingReportingOverflow(GeometryMesh.maximumPayloadBytes)
        guard !pointByteOverflow, !workingOverflow, !rasterAndPointOverflow, !meshOverflow,
              logicalBytes <= ReplayLimits.maximumLogicalCPUBytes else { throw ReplayFailure.resourceLimit }
        let views = try ordered.map { try map($0, cancellationCheck: cancellationCheck) }
        let sections = try extractSections(views, cancellationCheck: cancellationCheck)
        return ReplayAnalysis(views: views, sections: sections)
    }
    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func map(_ frame: ReplayFrame, cancellationCheck: () -> Bool) throws -> ReplayMappedView {
        guard let depth = frame.depth else { throw ReplayFailure.missingDepth }
        guard let mask = frame.mask else { throw ReplayFailure.missingMask }
        guard let confidence = frame.confidence else { throw ReplayFailure.invalidLayout }
        let c = frame.calibration
        let projector = try ReplayCameraMath.prepare(calibration: c, rasterWidth: depth.width,
            rasterHeight: depth.height, rotation: frame.rotation, semantics: frame.depthSemantics)
        guard frame.rotation != .unsupported else { throw ReplayFailure.unsupportedRotation }
        guard frame.maskRotation == frame.rotation else { throw ReplayFailure.maskAlignment }
        guard depth.width > 1, depth.height > 1, depth.width <= ReplayLimits.maximumRasterDimension,
              depth.height <= ReplayLimits.maximumRasterDimension else { throw ReplayFailure.resourceLimit }
        let (samples, overflow) = depth.width.multipliedReportingOverflow(by: depth.height)
        guard !overflow, samples <= ReplayLimits.maximumRasterSamples,
              mask.width > 1, mask.height > 1,
              mask.width <= ReplayLimits.maximumRasterDimension, mask.height <= ReplayLimits.maximumRasterDimension else {
            throw ReplayFailure.resourceLimit
        }
        guard confidence.width == depth.width, confidence.height == depth.height else { throw ReplayFailure.invalidLayout }
        let (maskSamples, maskOverflow) = mask.width.multipliedReportingOverflow(by: mask.height)
        guard !maskOverflow, maskSamples <= ReplayLimits.maximumRasterSamples else { throw ReplayFailure.resourceLimit }
        try validateRaster(depth, width: depth.width, height: depth.height, bytesPerPixel: 4)
        try validateRaster(mask, width: mask.width, height: mask.height, bytesPerPixel: 1)
        try validateRaster(confidence, width: depth.width, height: depth.height, bytesPerPixel: 1)
        var counts = ReplaySampleCounts()
        let result = try depth.bytes.withUnsafeBytes { (db: UnsafeRawBufferPointer) in
            try mask.bytes.withUnsafeBytes { (mb: UnsafeRawBufferPointer) in
                try confidence.bytes.withUnsafeBytes { (cb: UnsafeRawBufferPointer) -> [SIMD3<Double>] in
                    var points: [SIMD3<Double>] = []; points.reserveCapacity(samples)
                    for y in 0..<depth.height {
                        try check(cancellationCheck)
                        for x in 0..<depth.width {
                            counts.total += 1
                            let byteIndex = y * depth.bytesPerRow + x * 4
                            let maskX = min(mask.width - 1, Int((Double(x) + 0.5) / Double(depth.width) * Double(mask.width)))
                            let maskY = min(mask.height - 1, Int((Double(y) + 0.5) / Double(depth.height) * Double(mask.height)))
                            let maskIndex = maskY * mask.bytesPerRow + maskX
                            let confidenceIndex = y * confidence.bytesPerRow + x
                            guard mb[maskIndex] >= 128 else { counts.maskedOut += 1; continue }
                            let confidenceLevel = cb[confidenceIndex]
                            guard confidenceLevel <= 2 else { throw ReplayFailure.invalidLayout }
                            guard confidenceLevel == 2 else { counts.lowConfidence += 1; continue }
                            let bits = UInt32(db[byteIndex]) | UInt32(db[byteIndex+1]) << 8 | UInt32(db[byteIndex+2]) << 16 | UInt32(db[byteIndex+3]) << 24
                            let value = Double(Float(bitPattern: bits))
                            guard value.isFinite, (ReplayLimits.minimumDepth...ReplayLimits.maximumDepth).contains(value) else { throw ReplayFailure.invalidDepth }
                            let center = SIMD2(Double(x) + 0.5, Double(y) + 0.5)
                            let camera = try projector.cameraPoint(pixelCenter: center, depth: value)
                            // Pose was validated once before entering this private stage.
                            let world = frame.pose.translation + frame.pose.right * camera.x
                                + frame.pose.down * camera.y + frame.pose.forward * camera.z
                            guard world.x.isFinite, world.y.isFinite, world.z.isFinite else { throw ReplayFailure.invalidPose }
                            points.append(world)
                        }
                    }
                    return points
                }
            }
        }
        counts.accepted = result.count
        guard !result.isEmpty else { throw ReplayFailure.insufficientCoverage }
        return ReplayMappedView(view: frame.view, frameID: frame.frameID, captureID: frame.captureID,
                                referenceFrame: frame.pose.referenceFrame, pose: frame.pose, points: result, counts: counts)
    }

    private static func extractSections(_ views: [ReplayMappedView], cancellationCheck: () -> Bool) throws -> [ReplaySection] {
        guard views.count == 2, let front = views.first(where: {$0.view == .front}),
              let side = views.first(where: {$0.view == .side}) else { throw ReplayFailure.duplicateFrame }
        var sections: [ReplaySection] = []; sections.reserveCapacity(ReplayLimits.sectionHeights.count)
        for height in ReplayLimits.sectionHeights {
            try check(cancellationCheck)
            let fitF = try fit(front.points, height: height, cancellationCheck: cancellationCheck)
            let fitS = try fit(side.points, height: height, cancellationCheck: cancellationCheck)
            guard abs(fitF.width - fitS.width) <= ReplayLimits.viewExtentTolerance,
                  abs(fitF.depth - fitS.depth) <= ReplayLimits.viewExtentTolerance else { throw ReplayFailure.conflictingViews }
            let width = (fitF.width + fitS.width) * 0.5
            let depth = (fitF.depth + fitS.depth) * 0.5
            let angularSupportMask = try angularSupport(front.points, side.points, height: height,
                width: width, depth: depth, cancellationCheck: cancellationCheck)
            sections.append(ReplaySection(height: height, halfWidth: width, halfDepth: depth,
                frontSamples: fitF.samples, sideSamples: fitS.samples,
                maximumResidual: max(fitF.residual, fitS.residual), angularSupportMask: angularSupportMask))
        }
        return sections
    }
    /// A fixed policy grid discretizes observed centre-axis ellipse angles; a bin is supported
    /// by two or more depth samples from the union of the independently admitted views.
    private static func angularSupport(_ front: [SIMD3<Double>], _ side: [SIMD3<Double>],
                                       height: Double, width: Double, depth: Double,
                                       cancellationCheck: () -> Bool) throws -> UInt32 {
        var counts = [Int](repeating: 0, count: ReplayLimits.radialSegments)
        let fullTurn = 2 * Double.pi
        for viewIndex in 0..<2 {
            let points = viewIndex == 0 ? front : side
            for (index, point) in points.enumerated() {
                if index.isMultiple(of: 256) { try check(cancellationCheck) }
                guard abs(point.y - height) <= ReplayLimits.sectionHalfBand else { continue }
                var angle = atan2(point.z / depth, point.x / width)
                if angle < 0 { angle += fullTurn }
                let bin = min(ReplayLimits.radialSegments - 1,
                              Int(angle / fullTurn * Double(ReplayLimits.radialSegments)))
                counts[bin] += 1
            }
            if viewIndex == 0 { try check(cancellationCheck) }
        }
        var mask: UInt32 = 0
        for bin in counts.indices where counts[bin] >= ReplayLimits.minimumAngularSamplesPerBin {
            mask |= UInt32(1) << UInt32(bin)
        }
        return mask
    }

    private static func fit(_ points: [SIMD3<Double>], height: Double,
                            cancellationCheck: () -> Bool) throws -> (width: Double, depth: Double, residual: Double, samples: Int) {
        var aa = 0.0, ab = 0.0, bb = 0.0, ar = 0.0, br = 0.0
        var xMin = Double.infinity, xMax = -Double.infinity, zMin = Double.infinity, zMax = -Double.infinity
        var samples = 0
        for (index, p) in points.enumerated() {
            if index.isMultiple(of: 256) { try check(cancellationCheck) }
            guard abs(p.y - height) <= ReplayLimits.sectionHalfBand else { continue }
            samples += 1
            let x2 = p.x * p.x, z2 = p.z * p.z
            aa += x2*x2; ab += x2*z2; bb += z2*z2; ar += x2; br += z2
            xMin = min(xMin,p.x); xMax = max(xMax,p.x); zMin = min(zMin,p.z); zMax = max(zMax,p.z)
        }
        let determinant = aa*bb - ab*ab
        let conditionScale = aa * bb
        guard samples >= ReplayLimits.minimumPointsPerSectionView,
              determinant.isFinite, conditionScale.isFinite,
              determinant > max(1e-14, conditionScale * 1e-8),
              xMax-xMin > 0.02, zMax-zMin > 0.02 else { throw ReplayFailure.insufficientCoverage }
        let a = (ar*bb - br*ab) / determinant
        let b = (br*aa - ar*ab) / determinant
        guard a.isFinite, b.isFinite, a > 0, b > 0 else { throw ReplayFailure.insufficientCoverage }
        var residual = 0.0
        for (index, p) in points.enumerated() {
            if index.isMultiple(of: 256) { try check(cancellationCheck) }
            guard abs(p.y - height) <= ReplayLimits.sectionHalfBand else { continue }
            residual = max(residual, abs(a*p.x*p.x + b*p.z*p.z - 1))
        }
        guard residual <= ReplayLimits.maximumImplicitResidual else { throw ReplayFailure.conflictingViews }
        let width = 1 / sqrt(a), depth = 1 / sqrt(b)
        guard width.isFinite, depth.isFinite, (0.01...0.4).contains(width), (0.01...0.4).contains(depth) else { throw ReplayFailure.insufficientCoverage }
        return (width, depth, residual, samples)
    }

    private static func validateRaster(_ raster: ReplayRaster, width: Int, height: Int, bytesPerPixel: Int) throws {
        guard raster.width == width, raster.height == height, raster.width > 0, raster.height > 0 else { throw ReplayFailure.invalidLayout }
        let (rowMinimum, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !rowOverflow, raster.bytesPerRow >= rowMinimum else { throw ReplayFailure.invalidLayout }
        let (required, overflow) = raster.bytesPerRow.multipliedReportingOverflow(by: height)
        guard !overflow, required == raster.bytes.count else { throw ReplayFailure.invalidLayout }
        guard required <= ReplayLimits.maximumRasterBytes else { throw ReplayFailure.resourceLimit }
    }
    private static func check(_ check: () -> Bool) throws { if check() { throw ReplayFailure.cancelled } }
}
#endif
