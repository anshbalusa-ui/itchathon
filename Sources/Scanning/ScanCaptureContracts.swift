#if DEBUG
/// Capture observations, not a body model. Coordinates and quality are internal;
/// none of these values should be shown to a shopper or logged.
enum ScanCaptureView: String, Codable, Sendable { case front, side }
enum ScanViewEstimate: String, Codable, Sendable { case front, side, unverified }
enum ScanImageRotation: Int, Codable, CaseIterable, Sendable { case up, right, down, left }

struct ScanPoint: Equatable, Codable, Sendable {
    let x: Double
    let y: Double
}

struct ScanVector: Equatable, Codable, Sendable {
    let x: Double
    let y: Double
    let z: Double
}

struct ScanImageSize: Equatable, Codable, Sendable {
    let width: Int
    let height: Int
}

struct ScanCameraCalibration: Equatable, Codable, Sendable {
    /// Pinhole intrinsics in native RGB pixel coordinates, upper-left origin.
    let fx: Double
    let fy: Double
    let cx: Double
    let cy: Double
}

enum ScanJoint: String, Codable, CaseIterable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case leftShoulder, rightShoulder, leftHip, rightHip
    case leftAnkle, rightAnkle, leftWrist, rightWrist, leftKnee, rightKnee
}

struct ScanFrameMetadata: Equatable, Codable, Sendable {
    static let contractVersion = 1
    /// Monotonic capture-clock seconds, not wall-clock time; no epoch assumed.
    let timestamp: Double
    let imageSize: ScanImageSize
    let depthSize: ScanImageSize
    let maskSize: ScanImageSize
    /// Rotation taking native RGB/depth into an upright display image.
    let imageRotation: ScanImageRotation
    /// Rotation taking native RGB/depth into the mask's raster axes.
    let maskRotation: ScanImageRotation
    let calibration: ScanCameraCalibration
    /// Normalized native RGB coordinates, upper-left origin; not screen points.
    let landmarks: [ScanJoint: ScanPoint]
    /// AR world coordinates are an adapter detail; only within-session motion is used.
    let cameraPosition: ScanVector
    let cameraForward: ScanVector
}

struct ScanStabilityAnchor: Equatable, Sendable {
    let center: ScanPoint
    let height: Double
    let depth: Double
    let cameraPosition: ScanVector
    let cameraForward: ScanVector
}

enum ScanRejection: String, Equatable, Sendable {
    case missingPerson, multiplePeople, incompleteFraming, unreliablePose
    case invalidAlignment, unavailableDepth, insufficientPersonDepth, trackingLimited
    case unsupportedOrientation, unverifiedView, wrongView, holdStill, staleFrame
}

struct ScanFrameAssessment: Equatable, Sendable {
    let timestamp: Double
    let rejection: ScanRejection?
    /// A conservative sensor-derived cue, NOT hardware-validated view truth.
    let view: ScanViewEstimate
    let anchor: ScanStabilityAnchor?
}

enum ScanCameraPermission: Equatable, Sendable { case notDetermined, authorized, denied, restricted }
enum ScanUnavailableReason: Equatable, Sendable { case unsupportedDevice, cameraDenied, cameraRestricted }
enum ScanInterruption: Equatable, Sendable {
    case backgrounded, sessionInterrupted, trackingFailed, orientationChanged, personLost, timedOut
    case captureContextChanged
}
enum ScanCapturePhase: Equatable, Sendable {
    case idle, requestingPermission
    case scanning(ScanCaptureView)
    case retryRequired(ScanInterruption)
    case unavailable(ScanUnavailableReason)
    case candidatePairReady, cancelled
}
enum ScanStartAction: Equatable, Sendable {
    case none, requestPermission(UInt64), runSession(UInt64)
}

struct ScanFrameTicket: Equatable, Sendable {
    let generation: UInt64
    let sequence: UInt64
    let view: ScanCaptureView
    let timestamp: Double
    /// Local monotonic admission clock, separate from the camera clock.
    let receivedAt: Double
}

/// Read-only borrowed raster. The address is valid ONLY inside withPlanes;
/// consumers must not retain pointers or cross an asynchronous boundary.
struct ScanDepthPlane {
    let bytes: UnsafeRawBufferPointer
    let width: Int
    let height: Int
    let bytesPerRow: Int

    func value(x: Int, y: Int) -> Float {
        bytes.loadUnaligned(fromByteOffset: y * bytesPerRow + x * MemoryLayout<Float>.stride, as: Float.self)
    }
}

struct ScanBytePlane {
    let bytes: UnsafeRawBufferPointer
    let width: Int
    let height: Int
    let bytesPerRow: Int

    func value(x: Int, y: Int) -> UInt8 { bytes[y * bytesPerRow + x] }
}

/// Platform adapters own buffer lifetime and locking. Depth is Float32 metres,
/// confidence is UInt8 (0 low, 1 medium, 2 high), mask is UInt8 (0...255).
/// Depth/confidence share native RGB axes and field of view, at lower resolution.
/// Mask axes are declared in metadata. No CoreVideo/ARKit/Vision types cross here.
protocol ScanDepthEvidence: AnyObject {
    func withPlanes<Result>(
        _ body: (ScanDepthPlane, ScanBytePlane, ScanBytePlane) throws -> Result
    ) throws -> Result
}

struct ScanEvidenceFrame {
    let view: ScanCaptureView
    let metadata: ScanFrameMetadata
    let quality: ScanFrameAssessment
    let planes: any ScanDepthEvidence
}

/// Ephemeral input for later geometry research. A pair is not a reconstructed
/// body or an approved avatar profile. Orientation/thresholds require Segment 1B.
struct ScanEvidencePair {
    let front: ScanEvidenceFrame
    let side: ScanEvidenceFrame

    init?(front: ScanEvidenceFrame, side: ScanEvidenceFrame) {
        guard front.view == .front, side.view == .side,
              front.quality.rejection == nil, side.quality.rejection == nil,
              front.quality.view == .front, side.quality.view == .side,
              side.metadata.timestamp > front.metadata.timestamp,
              front.metadata.imageRotation == side.metadata.imageRotation else { return nil }
        self.front = front
        self.side = side
    }
}
#endif
