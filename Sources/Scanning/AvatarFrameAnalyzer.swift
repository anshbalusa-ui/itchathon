#if DEBUG
import CoreVideo
import Foundation
import ImageIO
import Vision

/// SDK-owned immutable frame buffers are retained across one worker hop.
/// Neither producer nor consumer mutates their contents; CPU access is read-only.
struct AppleScanFrameInput: @unchecked Sendable {
    let timestamp: Double
    let image: CVPixelBuffer
    let depth: CVPixelBuffer?
    let confidence: CVPixelBuffer?
    let imageRotation: ScanImageRotation
    let calibration: ScanCameraCalibration
    let cameraPosition: ScanVector
    let cameraForward: ScanVector
    let trackingNormal: Bool

    init(timestamp: Double, image: CVPixelBuffer, depth: CVPixelBuffer?, confidence: CVPixelBuffer?, imageRotation: ScanImageRotation, calibration: ScanCameraCalibration, cameraPosition: ScanVector, cameraForward: ScanVector, trackingNormal: Bool) {
        self.timestamp = timestamp; self.image = image; self.depth = depth; self.confidence = confidence
        self.imageRotation = imageRotation; self.calibration = calibration
        self.cameraPosition = cameraPosition; self.cameraForward = cameraForward; self.trackingNormal = trackingNormal
    }
}

struct AppleScanAnalysis {
    let assessment: ScanFrameAssessment
    let metadata: ScanFrameMetadata?
    let planes: (any ScanDepthEvidence)?
}
final class AvatarFrameAnalyzer {
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let maskRequest = VNGeneratePersonSegmentationRequest()
    private static let joints: [(ScanJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye),
        (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee)
    ]

    init() {
        maskRequest.qualityLevel = .balanced
        maskRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func analyze(_ input: AppleScanFrameInput) throws -> AppleScanAnalysis {
        let now = input.timestamp
        func failed(_ rejection: ScanRejection, _ view: ScanViewEstimate = .unverified) -> AppleScanAnalysis {
            AppleScanAnalysis(assessment: ScanFrameAssessment(timestamp: now, rejection: rejection, view: view, anchor: nil), metadata: nil, planes: nil)
        }
        let imageWidth = CVPixelBufferGetWidth(input.image), imageHeight = CVPixelBufferGetHeight(input.image)
        guard now.isFinite, imageWidth > 1, imageHeight > 1,
              input.calibration.fx.isFinite, input.calibration.fy.isFinite,
              input.calibration.cx.isFinite, input.calibration.cy.isFinite,
              input.calibration.fx > 0, input.calibration.fy > 0,
              input.calibration.cx >= 0, input.calibration.cx < Double(imageWidth),
              input.calibration.cy >= 0, input.calibration.cy < Double(imageHeight),
              input.cameraPosition.x.isFinite, input.cameraPosition.y.isFinite, input.cameraPosition.z.isFinite,
              input.cameraForward.x.isFinite, input.cameraForward.y.isFinite, input.cameraForward.z.isFinite else { return failed(.invalidAlignment) }
        guard input.trackingNormal else { return failed(.trackingLimited) }
        guard let depth = input.depth, let confidence = input.confidence else { return failed(.unavailableDepth) }
        let handler = VNImageRequestHandler(cvPixelBuffer: input.image, orientation: .up, options: [:])
        try handler.perform([maskRequest])
        let poseHandler = VNImageRequestHandler(cvPixelBuffer: input.image, orientation: Self.cgOrientation(input.imageRotation), options: [:])
        try poseHandler.perform([poseRequest])
        guard let poses = poseRequest.results, !poses.isEmpty else { return failed(.missingPerson) }
        guard poses.count == 1 else { return failed(.multiplePeople) }
        guard let mask = maskRequest.results?.first?.pixelBuffer else { return failed(.missingPerson) }
        let mw = CVPixelBufferGetWidth(mask), mh = CVPixelBufferGetHeight(mask)
        guard mw > 1, mh > 1, abs(Double(mw) / Double(mh) - Double(imageWidth) / Double(imageHeight)) < 0.015 else { return failed(.invalidAlignment) }

        var landmarks: [ScanJoint: ScanPoint] = [:]
        landmarks.reserveCapacity(Self.joints.count)
        let pose = poses[0]
        for (key, name) in Self.joints {
            guard let point = try? pose.recognizedPoint(name), point.confidence >= 0.35 else { continue }
            landmarks[key] = Self.nativeTopLeft(point.location, rotation: input.imageRotation)
        }
        let metadata = ScanFrameMetadata(timestamp: now, imageSize: ScanImageSize(width: imageWidth, height: imageHeight), depthSize: ScanImageSize(width: CVPixelBufferGetWidth(depth), height: CVPixelBufferGetHeight(depth)), maskSize: ScanImageSize(width: mw, height: mh), imageRotation: input.imageRotation, maskRotation: .up, calibration: input.calibration, landmarks: landmarks, cameraPosition: input.cameraPosition, cameraForward: input.cameraForward)
        guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
              CVPixelBufferGetWidth(depth) == CVPixelBufferGetWidth(confidence), CVPixelBufferGetHeight(depth) == CVPixelBufferGetHeight(confidence) else { return failed(.invalidAlignment) }
        let evidence = AppleScanEvidence(depth: depth, confidence: confidence, mask: mask)
        let result = try evidence.withPlanes { d, c, m in PersonDepthAligner.evaluate(depth: d, confidence: c, mask: m, metadata: metadata) }
        guard result.rejection == nil, let center = result.personCenter,
              let height = result.personHeight, let representativeDepth = result.representativeDepth else {
            return failed(result.rejection ?? .unreliablePose)
        }
        let view = PersonDepthAligner.estimateView(landmarks: landmarks,
                                                   shoulderAngle: result.shoulderAngle, hipAngle: result.hipAngle)
        guard view != .unverified else { return failed(.unverifiedView) }
        let anchor = ScanStabilityAnchor(center: center, height: height, depth: representativeDepth, cameraPosition: input.cameraPosition, cameraForward: input.cameraForward)
        return AppleScanAnalysis(assessment: ScanFrameAssessment(timestamp: now, rejection: nil, view: view, anchor: anchor), metadata: metadata, planes: evidence)
    }

    private static func cgOrientation(_ rotation: ScanImageRotation) -> CGImagePropertyOrientation {
        switch rotation { case .up: return .up; case .right: return .right; case .down: return .down; case .left: return .left }
    }

    /// Vision locations are lower-left upright. Convert through upper-left upright,
    /// then invert the native-to-upright EXIF rotation.
    static func nativeTopLeft(_ point: CGPoint, rotation: ScanImageRotation) -> ScanPoint {
        let x = Double(point.x), y = 1 - Double(point.y)
        switch rotation {
        case .up: return ScanPoint(x: x, y: y)
        case .right: return ScanPoint(x: y, y: 1 - x)
        case .down: return ScanPoint(x: 1 - x, y: 1 - y)
        case .left: return ScanPoint(x: 1 - y, y: x)
        }
    }
}
#endif
