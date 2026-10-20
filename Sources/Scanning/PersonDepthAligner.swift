#if DEBUG
import Foundation

/// Provisional evidence gates for Segment 1A; thresholds are not physically validated.
enum PersonDepthAligner {
    static let maskThreshold: UInt8 = 128
    static let minimumMaskFraction = 0.025
    static let minimumValidPersonDepthFraction = 0.80
    static let minimumValidRegionDepthFraction = 0.65
    static let minimumPersonDepthSamples = 30
    static let minimumRegionSamples = 8

    struct AxisAngle { let degrees: Double }
    struct Result {
        let rejection: ScanRejection?
        let personCenter: ScanPoint?
        let personHeight: Double?
        let representativeDepth: Double?
        let shoulderAngle: AxisAngle?
        let hipAngle: AxisAngle?
    }

    /// Accepts only calibrated, rotation-adjusted bilateral depth-axis angles.
    static func estimateView(landmarks: [ScanJoint: ScanPoint], imageRotation: ScanImageRotation, shoulderAngle: AxisAngle?, hipAngle: AxisAngle?) -> ScanViewEstimate {
        let bothFaceEyes = landmarks[.leftEye] != nil && landmarks[.rightEye] != nil
        let eyesAboveShoulders: Bool
        if let leftEye = landmarks[.leftEye], let rightEye = landmarks[.rightEye],
           let shoulderY = meanY(landmarks[.leftShoulder], landmarks[.rightShoulder], rotation: imageRotation) {
            eyesAboveShoulders = uprightPoint(leftEye, rotation: imageRotation).y < shoulderY
                && uprightPoint(rightEye, rotation: imageRotation).y < shoulderY
        } else {
            eyesAboveShoulders = false
        }
        let frontPose = landmarks[.nose] != nil && bothFaceEyes && eyesAboveShoulders
            && landmarks[.leftShoulder] != nil && landmarks[.rightShoulder] != nil
            && landmarks[.leftHip] != nil && landmarks[.rightHip] != nil
        if frontPose {
            guard let shoulderAngle, let hipAngle,
                  shoulderAngle.degrees <= 20, hipAngle.degrees <= 20 else { return .unverified }
            return .front
        }
        guard !bothFaceEyes, shoulderAngle != nil || hipAngle != nil else { return .unverified }
        if let shoulderAngle, shoulderAngle.degrees < 60 { return .unverified }
        if let hipAngle, hipAngle.degrees < 60 { return .unverified }
        return .side
    }

    /// Evaluates only pixel centers and validates every declared byte range before access.
    static func evaluate(depth: ScanDepthPlane, confidence: ScanBytePlane, mask: ScanBytePlane, metadata: ScanFrameMetadata) -> Result {
        let bad = Result(rejection: .invalidAlignment, personCenter: nil, personHeight: nil, representativeDepth: nil, shoulderAngle: nil, hipAngle: nil)
        let rgb = metadata.imageSize
        guard rgb.width > 1, rgb.height > 1, depth.width > 1, depth.height > 1,
              depth.width == confidence.width, depth.height == confidence.height, mask.width > 1, mask.height > 1,
              validStorage(width: depth.width, height: depth.height, row: depth.bytesPerRow, bytesPerPixel: 4, count: depth.bytes.count),
              validStorage(width: confidence.width, height: confidence.height, row: confidence.bytesPerRow, bytesPerPixel: 1, count: confidence.bytes.count),
              validStorage(width: mask.width, height: mask.height, row: mask.bytesPerRow, bytesPerPixel: 1, count: mask.bytes.count),
              sameAspect(width: depth.width, height: depth.height, rgb: rgb), sameAspect(width: mask.width, height: mask.height, rgb: rgb),
              metadata.depthSize == ScanImageSize(width: depth.width, height: depth.height),
              metadata.maskSize == ScanImageSize(width: mask.width, height: mask.height), metadata.maskRotation == .up,
              metadata.calibration.fx.isFinite, metadata.calibration.fy.isFinite,
              metadata.calibration.cx.isFinite, metadata.calibration.cy.isFinite,
              metadata.calibration.fx > 0, metadata.calibration.fy > 0,
              metadata.calibration.cx >= 0, metadata.calibration.cx < Double(rgb.width),
              metadata.calibration.cy >= 0, metadata.calibration.cy < Double(rgb.height) else { return bad }

        // Full raster inspection catches even a one-pixel clipped edge before bounded depth sampling.
        var maskPixels = 0, minX = mask.width, minY = mask.height, maxX = -1, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.value(x: x, y: y) >= maskThreshold {
                maskPixels += 1; minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maskPixels > 0 else { return result(.missingPerson) }
        guard minX > 0, minY > 0, maxX < mask.width - 1, maxY < mask.height - 1 else { return result(.incompleteFraming) }
        let bbox = uprightBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY, width: mask.width, height: mask.height, rotation: metadata.imageRotation)
        guard bbox.height >= 0.20 else { return result(.incompleteFraming) }

        let step = max(1, max(depth.width, depth.height) / 160)
        var sampleCount = 0, personSamples = 0, valid = 0, depthSum = 0.0
        var headCount = 0, torsoCount = 0, legCount = 0
        var headValid = 0, torsoValid = 0, legValid = 0
        for y in stride(from: 0, to: depth.height, by: step) {
            for x in stride(from: 0, to: depth.width, by: step) {
                sampleCount += 1
                let nx = (Double(x) + 0.5) / Double(depth.width), ny = (Double(y) + 0.5) / Double(depth.height)
                let mx = min(mask.width - 1, Int(nx * Double(mask.width))), my = min(mask.height - 1, Int(ny * Double(mask.height)))
                guard mask.value(x: mx, y: my) >= maskThreshold else { continue }
                personSamples += 1
                let up = uprightPoint(ScanPoint(x: nx, y: ny), rotation: metadata.imageRotation)
                let band = min(2, max(0, Int((up.y - bbox.minY) / bbox.height * 3)))
                if band == 0 { headCount += 1 } else if band == 1 { torsoCount += 1 } else { legCount += 1 }
                let z = Double(depth.value(x: x, y: y))
                let level = confidence.value(x: x, y: y)
                guard z.isFinite, (0.35...5.0).contains(z), (1...2).contains(level) else { continue }
                valid += 1; depthSum += z
                if band == 0 { headValid += 1 } else if band == 1 { torsoValid += 1 } else { legValid += 1 }
            }
        }
        guard personSamples > 0, Double(personSamples) / Double(max(1, sampleCount)) >= minimumMaskFraction else { return result(.incompleteFraming) }
        guard valid >= minimumPersonDepthSamples, Double(valid) / Double(personSamples) >= minimumValidPersonDepthFraction,
              headCount >= minimumRegionSamples, torsoCount >= minimumRegionSamples, legCount >= minimumRegionSamples,
              Double(headValid) / Double(headCount) >= minimumValidRegionDepthFraction,
              Double(torsoValid) / Double(torsoCount) >= minimumValidRegionDepthFraction,
              Double(legValid) / Double(legCount) >= minimumValidRegionDepthFraction else { return result(.insufficientPersonDepth) }

        let landmarks = metadata.landmarks
        guard landmarks.values.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              let head = landmarks[.nose] ?? landmarks[.leftEar] ?? landmarks[.rightEar],
              let shoulderY = meanY(landmarks[.leftShoulder], landmarks[.rightShoulder], rotation: metadata.imageRotation),
              let hipY = meanY(landmarks[.leftHip], landmarks[.rightHip], rotation: metadata.imageRotation),
              let ankleY = meanY(landmarks[.leftAnkle], landmarks[.rightAnkle], rotation: metadata.imageRotation) else { return result(.incompleteFraming) }
        let headY = uprightPoint(head, rotation: metadata.imageRotation).y
        guard headY < shoulderY, shoulderY < hipY, hipY < ankleY else { return result(.unreliablePose) }
        for point in landmarks.values {
            let mx = min(mask.width - 1, Int(point.x * Double(mask.width))), my = min(mask.height - 1, Int(point.y * Double(mask.height)))
            guard mask.value(x: mx, y: my) >= maskThreshold else { return result(.unreliablePose) }
        }
        let shoulder = calibratedAxis(.leftShoulder, .rightShoulder, landmarks: landmarks, depth: depth, confidence: confidence, mask: mask, metadata: metadata)
        let hip = calibratedAxis(.leftHip, .rightHip, landmarks: landmarks, depth: depth, confidence: confidence, mask: mask, metadata: metadata)
        return Result(rejection: nil,
                      personCenter: ScanPoint(x: (bbox.minX + bbox.maxX) / 2, y: (bbox.minY + bbox.maxY) / 2),
                      personHeight: bbox.height, representativeDepth: depthSum / Double(valid),
                      shoulderAngle: shoulder, hipAngle: hip)
    }

    private struct Bounds { let minX, maxX, minY, maxY: Double; var height: Double { maxY - minY } }
    private static func uprightBounds(minX: Int, minY: Int, maxX: Int, maxY: Int, width: Int, height: Int, rotation: ScanImageRotation) -> Bounds {
        let a = uprightPoint(ScanPoint(x: Double(minX) / Double(width), y: Double(minY) / Double(height)), rotation: rotation)
        let b = uprightPoint(ScanPoint(x: Double(maxX + 1) / Double(width), y: Double(maxY + 1) / Double(height)), rotation: rotation)
        let c = uprightPoint(ScanPoint(x: Double(maxX + 1) / Double(width), y: Double(minY) / Double(height)), rotation: rotation)
        let d = uprightPoint(ScanPoint(x: Double(minX) / Double(width), y: Double(maxY + 1) / Double(height)), rotation: rotation)
        return Bounds(minX: min(a.x,b.x,c.x,d.x), maxX: max(a.x,b.x,c.x,d.x), minY: min(a.y,b.y,c.y,d.y), maxY: max(a.y,b.y,c.y,d.y))
    }
    private static func uprightPoint(_ p: ScanPoint, rotation: ScanImageRotation) -> ScanPoint {
        switch rotation { case .up: return p; case .right: return ScanPoint(x: 1 - p.y, y: p.x); case .down: return ScanPoint(x: 1 - p.x, y: 1 - p.y); case .left: return ScanPoint(x: p.y, y: 1 - p.x) }
    }
    private static func meanY(_ a: ScanPoint?, _ b: ScanPoint?, rotation: ScanImageRotation) -> Double? {
        guard let point = a ?? b else { return nil }
        guard let b else { return uprightPoint(point, rotation: rotation).y }
        return (uprightPoint(point, rotation: rotation).y + uprightPoint(b, rotation: rotation).y) / 2
    }
    private static func calibratedAxis(_ lhs: ScanJoint, _ rhs: ScanJoint, landmarks: [ScanJoint: ScanPoint], depth: ScanDepthPlane, confidence: ScanBytePlane, mask: ScanBytePlane, metadata: ScanFrameMetadata) -> AxisAngle? {
        guard let a = landmarks[lhs], let b = landmarks[rhs],
              let pa = calibratedPoint(a, depth: depth, confidence: confidence, mask: mask, metadata: metadata),
              let pb = calibratedPoint(b, depth: depth, confidence: confidence, mask: mask, metadata: metadata),
              pa.pixelX != pb.pixelX || pa.pixelY != pb.pixelY else { return nil }
        let lateral: Double
        switch metadata.imageRotation { case .up: lateral = pb.x - pa.x; case .right: lateral = -(pb.y - pa.y); case .down: lateral = -(pb.x - pa.x); case .left: lateral = pb.y - pa.y }
        let depthDelta = pb.z - pa.z
        guard lateral != 0 || depthDelta != 0 else { return nil }
        let angle = atan2(abs(depthDelta), abs(lateral)) * 180 / .pi
        return angle.isFinite ? AxisAngle(degrees: angle) : nil
    }
    private struct CalibratedPixel { let x, y, z: Double; let pixelX, pixelY: Int }
    private static func calibratedPoint(_ point: ScanPoint, depth: ScanDepthPlane, confidence: ScanBytePlane, mask: ScanBytePlane, metadata: ScanFrameMetadata) -> CalibratedPixel? {
        let x = Int(point.x * Double(depth.width)), y = Int(point.y * Double(depth.height))
        guard x >= 0, y >= 0, x < depth.width, y < depth.height else { return nil }
        let nx = (Double(x) + 0.5) / Double(depth.width), ny = (Double(y) + 0.5) / Double(depth.height)
        let mx = min(mask.width - 1, Int(nx * Double(mask.width))), my = min(mask.height - 1, Int(ny * Double(mask.height)))
        let z = Double(depth.value(x: x, y: y)), c = metadata.calibration
        guard mask.value(x: mx, y: my) >= maskThreshold, confidence.value(x: x, y: y) == 2, z.isFinite, (0.35...5.0).contains(z) else { return nil }
        let rgbX = nx * Double(metadata.imageSize.width), rgbY = ny * Double(metadata.imageSize.height)
        return CalibratedPixel(x: (rgbX - c.cx) * z / c.fx, y: (rgbY - c.cy) * z / c.fy, z: z, pixelX: x, pixelY: y)
    }
    private static func validStorage(width: Int, height: Int, row: Int, bytesPerPixel: Int, count: Int) -> Bool {
        guard width > 0, height > 0, row >= 0, count >= 0 else { return false }
        let (minimumRow, rowOverflow) = width.multipliedReportingOverflow(by: bytesPerPixel)
        guard !rowOverflow, row >= minimumRow else { return false }
        let (required, sizeOverflow) = row.multipliedReportingOverflow(by: height)
        return !sizeOverflow && count >= required
    }
    private static func sameAspect(width: Int, height: Int, rgb: ScanImageSize) -> Bool {
        abs(Double(width) / Double(height) - Double(rgb.width) / Double(rgb.height)) < 0.015
    }
    private static func result(_ rejection: ScanRejection) -> Result {
        Result(rejection: rejection, personCenter: nil, personHeight: nil, representativeDepth: nil, shoulderAngle: nil, hipAngle: nil)
    }
}
#endif
