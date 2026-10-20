import ARKit
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Vision
import simd

struct AvatarPersonObservation {
    /// Pixel mask and landmarks refer to the same ARFrame camera image.
    let mask: CVPixelBuffer
    let landmarks: [String: CGPoint]
    let fullPersonVisible: Bool
    let poseReliable: Bool
    let torsoCenter: CGPoint?
}

/// Vision is used only to locate a person and their pose, never to claim
/// precise measurements from a silhouette.
struct AvatarPersonDetector {
    func analyze(_ cameraImage: CVPixelBuffer) throws -> AvatarPersonObservation? {
        let poseRequest = VNDetectHumanBodyPoseRequest()
        let maskRequest = VNGeneratePersonSegmentationRequest()
        maskRequest.qualityLevel = .balanced
        maskRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8

        // ARKit rear-camera buffers are sensor-oriented; this initial flow
        // locks the interface to portrait for a repeatable Vision transform.
        let handler = VNImageRequestHandler(
            cvPixelBuffer: cameraImage, orientation: .right, options: [:]
        )
        try handler.perform([poseRequest, maskRequest])

        guard let body = poseRequest.results?.first,
              let mask = maskRequest.results?.first?.pixelBuffer else {
            return nil
        }

        let joints: [(String, VNHumanBodyPoseObservation.JointName)] = [
            ("nose", .nose),
            ("leftShoulder", .leftShoulder),
            ("rightShoulder", .rightShoulder),
            ("leftHip", .leftHip),
            ("rightHip", .rightHip),
            ("leftAnkle", .leftAnkle),
            ("rightAnkle", .rightAnkle)
        ]
        var landmarks: [String: CGPoint] = [:]
        for (name, joint) in joints {
            if let point = try? body.recognizedPoint(joint), point.confidence >= 0.35 {
                landmarks[name] = point.location
            }
        }

        // In side views, one shoulder or hip can occlude the other.
        let trunk = ["leftShoulder", "rightShoulder", "leftHip", "rightHip"]
        let visibleTrunk = trunk.compactMap { landmarks[$0] }
        let shouldersVisible = landmarks["leftShoulder"] != nil
            || landmarks["rightShoulder"] != nil
        let hipsVisible = landmarks["leftHip"] != nil || landmarks["rightHip"] != nil
        let hasHeadAndFoot = landmarks["nose"] != nil
            && (landmarks["leftAnkle"] != nil || landmarks["rightAnkle"] != nil)
        let maskFramed = Self.personFitsInImage(mask)
        let center: CGPoint?
        if visibleTrunk.count >= 2 {
            center = CGPoint(
                x: visibleTrunk.reduce(0) { $0 + $1.x } / CGFloat(visibleTrunk.count),
                y: visibleTrunk.reduce(0) { $0 + $1.y } / CGFloat(visibleTrunk.count)
            )
        } else {
            center = nil
        }

        return AvatarPersonObservation(
            mask: mask,
            landmarks: landmarks,
            fullPersonVisible: maskFramed && hasHeadAndFoot,
            poseReliable: shouldersVisible && hipsVisible && hasHeadAndFoot,
            torsoCenter: center
        )
    }

    private static func personFitsInImage(_ mask: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return false }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let step = max(1, min(width, height) / 90)
        var count = 0
        var total = 0
        var minX = width, minY = height, maxX = 0, maxY = 0

        for y in Swift.stride(from: 0, to: height, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in Swift.stride(from: 0, to: width, by: step) {
                total += 1
                if row[x] > 128 {
                    count += 1
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard total > 0, Double(count) / Double(total) >= 0.035 else { return false }
        let marginX = max(1, width / 65)
        let marginY = max(1, height / 65)
        return minX > marginX && minY > marginY
            && maxX < width - marginX && maxY < height - marginY
    }
}

/// Checks that the camera is supplying actual usable scene depth. The check
/// is deliberately NOT a validated measurement of the person's body.
enum AvatarDepthInspector {
    static func hasUsableDepth(_ depth: ARDepthData) -> Bool {
        let map = depth.depthMap
        guard let confidence = depth.confidenceMap,
              CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(map) == CVPixelBufferGetWidth(confidence),
              CVPixelBufferGetHeight(map) == CVPixelBufferGetHeight(confidence),
              CVPixelBufferLockBaseAddress(map, .readOnly) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else {
            return false
        }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }

        guard let depthBase = CVPixelBufferGetBaseAddress(map),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else {
            return false
        }

        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let depthStride = CVPixelBufferGetBytesPerRow(map)
        let confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
        let step = max(1, min(width, height) / 35)
        var valid = 0, samples = 0
        for y in Swift.stride(from: 0, to: height, by: step) {
            let d = depthBase.advanced(by: y * depthStride).assumingMemoryBound(to: Float.self)
            let c = confidenceBase.advanced(by: y * confidenceStride).assumingMemoryBound(to: UInt8.self)
            for x in Swift.stride(from: 0, to: width, by: step) {
                samples += 1
                if d[x].isFinite && d[x] >= 0.35 && d[x] <= 5.0 && c[x] >= 1 {
                    valid += 1
                }
            }
        }
        return samples > 0 && Double(valid) / Double(samples) >= 0.35
    }
}

/// In-memory only: no image, mask, or depth buffer is written to disk.
struct AvatarScanSnapshot {
    let cameraImage: CVPixelBuffer
    let depthMap: CVPixelBuffer
    let confidenceMap: CVPixelBuffer
    let personMask: CVPixelBuffer
    let cameraIntrinsics: simd_float3x3
    let cameraResolution: CGSize
    let timestamp: TimeInterval
    let landmarks: [String: CGPoint]
    let angle: AvatarCapturePhase
}

struct AvatarScanCapture {
    let front: AvatarScanSnapshot
    let side: AvatarScanSnapshot
}
