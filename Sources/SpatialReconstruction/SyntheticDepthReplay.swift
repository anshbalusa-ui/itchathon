#if DEBUG
import Foundation

/// Authority minted only by this deterministic, first-party ray-cast simulator.
/// It deliberately contains no reference geometry or parameters.
struct ReviewedSyntheticReplay: Sendable {
    let id: ReplayID
    let frames: [ReplayFrame]
    let evaluationTimestamp: Double
    let schemaVersion: Int
    let capability: SyntheticReplayCapability

    fileprivate init(id: ReplayID, frames: [ReplayFrame], evaluationTimestamp: Double) {
        self.id = id
        self.frames = frames
        self.evaluationTimestamp = evaluationTimestamp
        self.schemaVersion = ReplayLimits.schemaVersion
        self.capability = .firstPartyRayCastV1
    }
}

enum SyntheticReplayCapability: Equatable, Sendable {
    case firstPartyRayCastV1
}

/// Test-only descriptive ground truth. Reconstruction code must use only ReplayFrame.
struct SyntheticReplayReference: Equatable, Sendable {
    let halfWidth: Double
    let halfDepth: Double
    let minimumY: Double
    let maximumY: Double
}

enum SyntheticDepthReplayFactory {
    private static let width = 128
    private static let height = 96
    private static let imageWidth = 320
    private static let imageHeight = 240
    private static let worldFrame = "synthetic-world-y-up-v1"

    static func reference(for id: ReplayID) -> SyntheticReplayReference {
        scene(for: id)
    }

    private static func scene(for id: ReplayID) -> SyntheticReplayReference {
        let b = id == .columnB
        return SyntheticReplayReference(halfWidth: b ? 0.14 : 0.20,
                                        halfDepth: b ? 0.20 : 0.12,
                                        minimumY: 0.35, maximumY: 1.45)
    }

    static func make(_ id: ReplayID, cancellationCheck: () -> Bool = { Task.isCancelled }) throws -> ReviewedSyntheticReplay {
        try checkCancellation(cancellationCheck)
        let (frontPose, sidePose) = poses(for: id)
        let parameters = scene(for: id)
        let front = try render(view: .front, pose: frontPose, id: id, reference: parameters,
                               cancellationCheck: cancellationCheck)
        let sideReference = id == .conflictingViews ? scene(for: .columnB) : parameters
        let side = try render(view: .side, pose: sidePose, id: id, reference: sideReference,
                              cancellationCheck: cancellationCheck)
        var frames = [front, side]
        var evaluation = 10.25
        switch id {
        case .missingDepth:
            frames[0].depth = nil
        case .badCalibration:
            frames[0].calibration.fx = 0
        case .inconsistentPose:
            frames[1].pose.translation.x += 0.15
        case .missingMask:
            frames[0].mask = nil
        case .misalignedMask:
            frames[0].maskRotation = frames[0].rotation == .right ? .down : .right
        case .lowConfidence:
            frames = try frames.map { try replacingConfidence($0, with: 0, cancellationCheck: cancellationCheck) }
        case .duplicateFrame:
            frames[1].frameID = frames[0].frameID
            frames[1].sequence = frames[0].sequence
        case .staleFrame:
            evaluation = 20.25
        case .unverifiedSource:
            frames[0].source = .unverifiedLiveSensor
        default:
            break
        }
        try checkCancellation(cancellationCheck)
        return ReviewedSyntheticReplay(id: id, frames: frames,
                                       evaluationTimestamp: evaluation)
    }

    private static func poses(for id: ReplayID) -> (ReplayPose, ReplayPose) {
        let moved = id == .movedCameraA

        let frontOrigin = SIMD3<Double>(moved ? -0.12 : 0, moved ? 0.96 : 0.9, moved ? 2.35 : 2)
        let sideOrigin = SIMD3<Double>(moved ? 2.35 : 2, moved ? 0.96 : 0.9, moved ? 0.12 : 0)
        func basis(_ origin: SIMD3<Double>) -> (right: SIMD3<Double>, down: SIMD3<Double>, forward: SIMD3<Double>) {
            let delta = SIMD3<Double>(-origin.x, 0.9 - origin.y, -origin.z)
            let forward = delta / sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
            let rightRaw = SIMD3<Double>(-forward.z, 0, forward.x)
            let right = rightRaw / sqrt(rightRaw.x * rightRaw.x + rightRaw.z * rightRaw.z)
            let downRaw = SIMD3<Double>(forward.y * right.z - forward.z * right.y,
                                        forward.z * right.x - forward.x * right.z,
                                        forward.x * right.y - forward.y * right.x)
            let down = downRaw / sqrt(downRaw.x * downRaw.x + downRaw.y * downRaw.y + downRaw.z * downRaw.z)
            return (right, down, forward)
        }
        func front() -> ReplayPose {
            if moved {
                let axes = basis(frontOrigin)
                return ReplayPose(translation: frontOrigin, right: axes.right,
                                  down: axes.down, forward: axes.forward, referenceFrame: worldFrame)
            }
            return ReplayPose(translation: frontOrigin, right: SIMD3(1, 0, 0),
                              down: SIMD3(0, -1, 0), forward: SIMD3(0, 0, -1), referenceFrame: worldFrame)
        }
        func side() -> ReplayPose {
            if moved {
                let axes = basis(sideOrigin)
                return ReplayPose(translation: sideOrigin, right: axes.right,
                                  down: axes.down, forward: axes.forward, referenceFrame: worldFrame)
            }
            return ReplayPose(translation: sideOrigin, right: SIMD3(0, 0, -1),
                              down: SIMD3(0, -1, 0), forward: SIMD3(-1, 0, 0), referenceFrame: worldFrame)
        }
        return (front(), side())
    }

    private static func render(view: ReplayView, pose: ReplayPose, id: ReplayID,
                               reference: SyntheticReplayReference,
                               cancellationCheck: () -> Bool) throws -> ReplayFrame {
        let changedCalibration = id == .changedCalibrationA
        let imageW = changedCalibration ? 640 : imageWidth
        let imageH = changedCalibration ? 480 : imageHeight
        // More real rays resolve the narrow surviving overlap; the original coarse
        // occlusion remains a negative replay rather than weakening angular admission.
        let rasterW = id == .partialOcclusionA ? 192 : (changedCalibration || id == .anisotropicRasterA ? 160 : width)
        let rasterH = id == .partialOcclusionA ? 144 : (changedCalibration ? 120 : height)
        let fx = changedCalibration ? 493.0 : 260.0
        let fy = changedCalibration ? 437.0 : 290.0
        let sdkPixelOrigin = id == .sdkPixelOriginA
        let rawCx = Double(imageW) / 2, rawCy = Double(imageH) / 2
        let cx = rawCx - (sdkPixelOrigin ? 0.5 : 0)
        let cy = rawCy - (sdkPixelOrigin ? 0.5 : 0)
        let rotated = id == .rotatedRasterA
        let storedW = rotated ? rasterH : rasterW
        let storedH = rotated ? rasterW : rasterH
        let depthStride = storedW * 4 + 16
        let scalarStride = storedW + 8
        let (depthCount, depthOverflow) = depthStride.multipliedReportingOverflow(by: storedH)
        let (scalarCount, scalarOverflow) = scalarStride.multipliedReportingOverflow(by: storedH)
        let (samples, sampleOverflow) = rasterW.multipliedReportingOverflow(by: rasterH)
        let (scalarBytes, scalarBytesOverflow) = scalarCount.multipliedReportingOverflow(by: 2)
        let (frameBytes, byteOverflow) = depthCount.addingReportingOverflow(scalarBytes)
        guard rasterW <= ReplayLimits.maximumRasterDimension, rasterH <= ReplayLimits.maximumRasterDimension,
              !sampleOverflow, samples <= ReplayLimits.maximumRasterSamples,
              !depthOverflow, !scalarOverflow, !scalarBytesOverflow, !byteOverflow,
              frameBytes <= ReplayLimits.maximumRasterBytes / ReplayLimits.maximumFrames else { throw ReplayFailure.resourceLimit }
        var depth = Data(count: depthCount)
        var confidence = Data(count: scalarCount)
        var mask = Data(count: scalarCount)
        let radii = reference
        try depth.withUnsafeMutableBytes { (depthBytes: UnsafeMutableRawBufferPointer) in
            try confidence.withUnsafeMutableBytes { (confidenceBytes: UnsafeMutableRawBufferPointer) in
                try mask.withUnsafeMutableBytes { (maskBytes: UnsafeMutableRawBufferPointer) in
                    for y in 0..<rasterH {
                        if y & 7 == 0 { try checkCancellation(cancellationCheck) }
                        for x in 0..<rasterW {
                            let rgbX = (Double(x) + 0.5) * Double(imageW) / Double(rasterW)
                            let rgbY = (Double(y) + 0.5) * Double(imageH) / Double(rasterH)
                            let nx = (rgbX - cx - (sdkPixelOrigin ? 0.5 : 0)) / fx
                            let ny = (rgbY - cy - (sdkPixelOrigin ? 0.5 : 0)) / fy
                            let ray = pose.right * nx + pose.down * ny + pose.forward
                            guard let opticalDepth = intersect(origin: pose.translation, ray: ray, reference: radii) else { continue }
                            let worldPoint = pose.translation + ray * opticalDepth
                            let normalizedHeight = (worldPoint.y - radii.minimumY) / (radii.maximumY - radii.minimumY)
                            if (id == .partialOcclusionA || id == .occlusionGap),
                               normalizedHeight > 0.43, normalizedHeight < 0.57,
                               (view == .front ? nx > 0.03 : nx > 0.02) { continue }
                            let value = id == .rayDistanceA ? opticalDepth * sqrt(ray.x * ray.x + ray.y * ray.y + ray.z * ray.z) : opticalDepth
                            let (storedX, storedY) = rotated ? (rasterH - 1 - y, x) : (x, y)
                            let dOffset = storedY * depthStride + storedX * 4
                            let bits = Float(value).bitPattern.littleEndian
                            depthBytes[dOffset] = UInt8(truncatingIfNeeded: bits)
                            depthBytes[dOffset + 1] = UInt8(truncatingIfNeeded: bits >> 8)
                            depthBytes[dOffset + 2] = UInt8(truncatingIfNeeded: bits >> 16)
                            depthBytes[dOffset + 3] = UInt8(truncatingIfNeeded: bits >> 24)
                            let byteOffset = storedY * scalarStride + storedX
                            confidenceBytes[byteOffset] = 2
                            maskBytes[byteOffset] = 255
                        }
                    }
                }
            }
        }
        let rotation: ReplayRotation = rotated ? .right : .up
        return ReplayFrame(captureID: "synthetic-capture-\(id.rawValue)-v1", frameID: view == .front ? "front" : "side",
                           sequence: view == .front ? 1 : 2,
                           timestamp: view == .front ? 10 : 10.1, view: view,
                           calibration: ReplayCalibration(imageWidth: imageW, imageHeight: imageH,
                                                          fx: fx, fy: fy, cx: cx, cy: cy,
                                                          origin: sdkPixelOrigin ? .upperLeftPixelCenter : .rasterCorner),
                           pose: pose, depthSemantics: id == .rayDistanceA ? .euclideanRayDistance : .opticalAxis,
                           rotation: rotation, maskRotation: rotation, registration: .sharedFieldOfViewPixelCenters,
                           depth: raster(storedW, storedH, depthStride, depth),
                           confidence: raster(storedW, storedH, scalarStride, confidence),
                           mask: raster(storedW, storedH, scalarStride, mask))
    }

    private static func intersect(origin: SIMD3<Double>, ray: SIMD3<Double>,
                                  reference: SyntheticReplayReference) -> Double? {
        let a = ray.x * ray.x / (reference.halfWidth * reference.halfWidth)
            + ray.z * ray.z / (reference.halfDepth * reference.halfDepth)
        let b = 2 * (origin.x * ray.x / (reference.halfWidth * reference.halfWidth)
            + origin.z * ray.z / (reference.halfDepth * reference.halfDepth))
        let c = origin.x * origin.x / (reference.halfWidth * reference.halfWidth)
            + origin.z * origin.z / (reference.halfDepth * reference.halfDepth) - 1
        var nearest = Double.infinity
        if a > 1e-15 {
            let discriminant = b * b - 4 * a * c
            if discriminant >= 0 {
                let root = sqrt(discriminant)
                let nearer = (-b - root) / (2 * a), farther = (-b + root) / (2 * a)
                for index in 0..<2 {
                    let t = index == 0 ? nearer : farther
                    guard t > 0, t < nearest else { continue }
                    let y = origin.y + t * ray.y
                    if y >= reference.minimumY && y <= reference.maximumY { nearest = t }
                }
            }
        }
        if abs(ray.y) > 1e-15 {
            for capIndex in 0..<2 {
                let capY = capIndex == 0 ? reference.minimumY : reference.maximumY
                let t = (capY - origin.y) / ray.y
                guard t > 0, t < nearest else { continue }
                let x = origin.x + t * ray.x, z = origin.z + t * ray.z
                if x * x / (reference.halfWidth * reference.halfWidth)
                    + z * z / (reference.halfDepth * reference.halfDepth) <= 1 { nearest = t }
            }
        }
        return nearest.isFinite ? nearest : nil
    }

    private static func replacingConfidence(_ frame: ReplayFrame, with value: UInt8,
                                            cancellationCheck: () -> Bool) throws -> ReplayFrame {
        guard var raster = frame.confidence else { return frame }
        try checkCancellation(cancellationCheck)
        try raster.bytes.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            for y in 0..<raster.height {
                if y & 15 == 0 { try checkCancellation(cancellationCheck) }
                for x in 0..<raster.width { bytes[y * raster.bytesPerRow + x] = value }
            }
        }
        var result = frame
        result.confidence = raster
        return result
    }

    private static func raster(_ width: Int, _ height: Int, _ stride: Int, _ bytes: Data) -> ReplayRaster {
        ReplayRaster(width: width, height: height, bytesPerRow: stride, bytes: bytes)
    }

    private static func checkCancellation(_ check: () -> Bool) throws {
        if check() { throw ReplayFailure.cancelled }
    }
}
#endif
