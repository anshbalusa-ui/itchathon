#if DEBUG
import Foundation

/// Owned numerical replay inputs, never borrowed live camera evidence.
enum ReplayID: String, CaseIterable, Identifiable, Sendable {
    case columnA, columnB, movedCameraA, changedCalibrationA, rotatedRasterA, rayDistanceA, partialOcclusionA, sdkPixelOriginA
    case missingDepth, badCalibration, conflictingViews, inconsistentPose, missingMask, misalignedMask, lowConfidence, duplicateFrame, staleFrame
    var id: String { rawValue }
    case unverifiedSource
    case anisotropicRasterA
    case occlusionGap
    var title: String {
        switch self {
        case .columnA: "Simulated column A"
        case .columnB: "Simulated column B"
        case .movedCameraA: "Simulated A — moved cameras"
        case .changedCalibrationA: "Simulated A — changed calibration"
        case .rotatedRasterA: "Simulated A — rotated raster"
        case .rayDistanceA: "Simulated A — ray-distance depth"
        case .partialOcclusionA: "Simulated A — partial occlusion"
        case .sdkPixelOriginA: "Simulated A — explicit SDK pixel origin"
        case .anisotropicRasterA: "Simulated A — anisotropic raster sampling"
        case .missingDepth: "Simulated missing depth"
        case .badCalibration: "Simulated invalid calibration"
        case .conflictingViews: "Simulated conflicting views"
        case .inconsistentPose: "Simulated inconsistent pose"
        case .missingMask: "Simulated missing mask"
        case .misalignedMask: "Simulated unregistered mask"
        case .lowConfidence: "Simulated low-confidence depth"
        case .duplicateFrame: "Simulated duplicate frame"
        case .staleFrame: "Simulated stale frame"
        case .unverifiedSource: "Simulated unverified live-source rejection"
        case .occlusionGap: "Simulated unsupported occlusion gap"
        }
    }
}

enum ReplayFailure: Error, Equatable, LocalizedError, Sendable {
    case cancelled, unsupportedVersion, unverifiedSource, invalidCalibration, invalidPose
    case unsupportedConvention, unsupportedUnits, unsupportedRotation, invalidLayout, resourceLimit
    case missingDepth, missingMask, maskAlignment, invalidDepth, insufficientCoverage
    case inconsistentCapture, duplicateFrame, staleFrame, conflictingViews, invalidMesh
    var errorDescription: String? {
        switch self {
        case .cancelled: "Synthetic reconstruction was cancelled."
        case .unsupportedVersion: "This replay schema or reconstruction capability is unsupported."
        case .unverifiedSource: "Only reviewed simulated replay observations are admitted. Live sensor evidence is not authorized."
        case .invalidCalibration: "Synthetic camera calibration is invalid or incompatible with its raster."
        case .invalidPose: "The camera-to-world transform is invalid or inconsistent."
        case .unsupportedConvention: "The declared coordinate, pixel or depth convention is unsupported."
        case .unsupportedUnits: "Only the declared metre scale is supported."
        case .unsupportedRotation: "The declared raster rotation is unsupported."
        case .invalidLayout: "The raster dimensions, byte stride or storage length are invalid."
        case .resourceLimit: "The replay exceeds the bounded reconstruction budget."
        case .missingDepth: "Required synthetic depth is missing. No surface was substituted."
        case .missingMask: "Required synthetic segmentation is missing."
        case .maskAlignment: "The mask and depth do not declare supported pixel registration."
        case .invalidDepth: "An eligible synthetic depth sample is nonfinite or outside the supported range."
        case .insufficientCoverage: "Required sections lack supported front and side observations. Unknown regions were not filled in."
        case .inconsistentCapture: "The views do not share a compatible synthetic capture and reference frame."
        case .duplicateFrame: "Distinct ordered front and side frames are required."
        case .staleFrame: "The synthetic frames are stale or incorrectly time-ordered."
        case .conflictingViews: "The mapped front and side observations disagree beyond simulation tolerances."
        case .invalidMesh: "The observation-derived synthetic mesh failed validation."
        }
    }
}

enum ReplayLimits {
    static let schemaVersion = 1
    static let maximumFrames = 2
    static let maximumRasterDimension = 256
    static let maximumRasterSamples = 49_152
    static let maximumRasterBytes = 1_048_576
    static let maximumPoints = 98_304
    static let maximumLogicalCPUBytes = 8_388_608
    static let sectionHeights: [Double] = [0.45, 0.62, 0.79, 0.96, 1.13, 1.30]
    static let sectionHalfBand = 0.025
    static let radialSegments = 24
    static let minimumSupportedAngularVertices = 8
    static let minimumAngularSamplesPerBin = 2
    static let minimumCameraBaseline = 0.5
    static let maximumCameraTranslation = 4.0
    static let minimumPointsPerSectionView = 16
    static let viewExtentTolerance = 0.003
    static let maximumImplicitResidual = 0.015
    static let minimumDepth = 0.1
    static let maximumDepth = 4.0
    static let maximumFrameAge = 1.0
    static let maximumPairInterval = 0.5
}

enum ReplayView: String, Equatable, Sendable { case front, side }
enum ReplaySource: Equatable, Sendable { case reviewedSimulation, unverifiedLiveSensor, unknown }
enum ReplayUnits: Equatable, Sendable { case metres, centimetres, unknown }
enum ReplayDepthSemantics: Equatable, Sendable { case opticalAxis, euclideanRayDistance, unknown }
enum ReplayRotation: Int, Equatable, Sendable { case up = 0, right = 90, down = 180, left = 270, unsupported = 45 }
enum ReplayTransformDirection: Equatable, Sendable { case opticalToWorld, worldToOptical }
enum ReplayHandedness: Equatable, Sendable { case rightHanded, reflected }
enum ReplayRegistration: Equatable, Sendable { case sharedFieldOfViewPixelCenters, unknown }
enum ReplayPixelConvention: Equatable, Sendable { case topLeftCenters, bottomLeft, unknown }
enum ReplayDepthEncoding: Equatable, Sendable { case float32LittleEndian, unknown }

/// Calibration origin is separate from the stored raster's corner-origin centres.
enum ReplayIntrinsicsOrigin: Equatable, Sendable { case rasterCorner, upperLeftPixelCenter, unknown }

struct ReplayCalibration: Equatable, Sendable {
    var imageWidth: Int
    var imageHeight: Int
    var fx: Double
    var fy: Double
    var cx: Double
    var cy: Double
    var origin: ReplayIntrinsicsOrigin = .rasterCorner
}

/// Optical basis is right/down/forward; right × down = forward. World is +Y up.
/// ARKit camera basis conversion is NOT inferred from S1A's coarse motion cues.
struct ReplayPose: Equatable, Sendable {
    var translation: SIMD3<Double>
    var right: SIMD3<Double>
    var down: SIMD3<Double>
    var forward: SIMD3<Double>
    var homogeneousRow: SIMD4<Double> = SIMD4(0, 0, 0, 1)
    var direction: ReplayTransformDirection = .opticalToWorld
    var handedness: ReplayHandedness = .rightHanded
    var scale: Double = 1
    var referenceFrame: String = "synthetic-world-y-up-v1"
}

struct ReplayRaster: Equatable, Sendable {
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var bytes: Data
}

struct ReplayFrame: Equatable, Sendable {
    var schemaVersion: Int = 1
    var source: ReplaySource = .reviewedSimulation
    var captureID: String
    var frameID: String
    var subject: String = "fictional-geometric-object"
    var sequence: UInt64
    var timestamp: Double
    var view: ReplayView
    var calibration: ReplayCalibration
    var pose: ReplayPose
    var units: ReplayUnits = .metres
    var metresPerUnit: Double = 1
    var pixelConvention: ReplayPixelConvention = .topLeftCenters
    var depthSemantics: ReplayDepthSemantics = .opticalAxis
    var depthEncoding: ReplayDepthEncoding = .float32LittleEndian
    var rotation: ReplayRotation = .up
    var maskRotation: ReplayRotation = .up
    var registration: ReplayRegistration = .sharedFieldOfViewPixelCenters
    var depth: ReplayRaster?
    var confidence: ReplayRaster?
    var mask: ReplayRaster?
}

struct ReplaySampleCounts: Equatable, Sendable {
    var total = 0
    var maskedOut = 0
    var lowConfidence = 0
    var accepted = 0
}

struct ReplayMappedView: Equatable, Sendable {
    let view: ReplayView
    let frameID: String
    let captureID: String
    let referenceFrame: String
    let pose: ReplayPose
    let points: [SIMD3<Double>]
    let counts: ReplaySampleCounts
}

struct ReplaySection: Equatable, Sendable {
    let height: Double
    let halfWidth: Double
    let halfDepth: Double
    let frontSamples: Int
    let sideSamples: Int
    let maximumResidual: Double
    let angularSupportMask: UInt32
}

struct ReplayMappingSummary: Equatable, Sendable {
    let view: ReplayView
    let frameID: String
    let captureID: String
    let referenceFrame: String
    let counts: ReplaySampleCounts
    let minimum: SIMD3<Double>
    let maximum: SIMD3<Double>
}

struct ReplayAnalysis: Sendable {
    let views: [ReplayMappedView]
    let sections: [ReplaySection]
}

enum ReplayStage: String, CaseIterable, Equatable, Sendable {
    case framesValidated = "Simulated frames and calibration validated"
    case pointsMapped = "Depth points mapped into common coordinates"
    case viewsRegistered = "Front and side observations compatible"
    case sectionsExtracted = "Required synthetic sections supported"
    case meshGenerated = "Observation-derived surface generated"
}

protocol ReplayReconstructing: Sendable {
    func reconstruct(_ replay: ReplayID) async throws -> ReplayGeometryResult
}
#endif
