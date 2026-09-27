import Foundation

struct BodyScanInput {
    let chestWidth: Double
    let chestDepth: Double
    let waistWidth: Double
    let waistDepth: Double
    let shoulderWidth: Double
    let torsoLength: Double
}

protocol BodyScanning {
    func scan(_ input: BodyScanInput) throws -> BodyProfile
}

enum BodyScanError: LocalizedError {
    case unavailable
    case unsupportedDepth
    case cameraDenied
    case invalidDepth
    case invalidGeometry
    case insufficientConfidence
    case interrupted
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Body scanning is not available on this device."
        case .unsupportedDepth:
            return "This device does not support the required depth capture."
        case .cameraDenied:
            return "Camera access is required to scan your body. Allow access in Settings or enter measurements manually."
        case .invalidDepth:
            return "The depth measurement was invalid. Reposition and try again."
        case .invalidGeometry:
            return "The captured body measurements were invalid or out of range."
        case .insufficientConfidence:
            return "The scan was not confident enough. Try again with better lighting and your full upper body visible."
        case .interrupted:
            return "The scan was interrupted. Start a new scan to continue."
        case .cancelled:
            return "The scan was cancelled."
        }
    }
}

struct GuidedBodyScanService: BodyScanning {
    static let chestCalibrationMultiplier = 1.0
    static let waistCalibrationMultiplier = 1.0

    func scan(_ input: BodyScanInput) throws -> BodyProfile {
        guard validLength(input.chestWidth), validLength(input.chestDepth),
              validLength(input.waistWidth), validLength(input.waistDepth),
              validLength(input.shoulderWidth), validLength(input.torsoLength) else {
            throw BodyScanError.invalidGeometry
        }

        let chest: Double
        let waist: Double
        do {
            chest = try BodyGeometry.circumference(
                width: input.chestWidth, depth: input.chestDepth
            ) * Self.chestCalibrationMultiplier
            waist = try BodyGeometry.circumference(
                width: input.waistWidth, depth: input.waistDepth
            ) * Self.waistCalibrationMultiplier
        } catch {
            throw BodyScanError.invalidGeometry
        }

        guard chest.isFinite, chest > 0, waist.isFinite, waist > 0 else {
            throw BodyScanError.invalidGeometry
        }

        let origin = MeasurementOrigin(source: .bodyScan)
        return BodyProfile(
            chestCircumference: chest,
            waistCircumference: waist,
            hipCircumference: 0,
            shoulderWidth: input.shoulderWidth,
            torsoLength: input.torsoLength,
            origins: [
                MeasurementKey.chestCircumference.rawValue: origin,
                MeasurementKey.waistCircumference.rawValue: origin,
                MeasurementKey.shoulderWidth.rawValue: origin,
                MeasurementKey.torsoLength.rawValue: origin
            ]
        )
    }
}
