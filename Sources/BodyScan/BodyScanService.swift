import Foundation

protocol BodyScanning {
    func scan() async throws -> BodyProfile
}

enum BodyScanError: LocalizedError {
    case unavailable
    case insufficientConfidence

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Body scanning is not available on this device."
        case .insufficientConfidence:
            return "The scan was not confident enough. Try again with better lighting and your full upper body visible."
        }
    }
}

/// Placeholder for the next implementation pass.
///
/// Recommended pipeline:
/// 1. Vision human-body pose landmarks.
/// 2. ARKit/LiDAR depth around left/right landmarks.
/// 3. Convert image-space landmarks to metric world-space points.
/// 4. Estimate shoulder width directly.
/// 5. Estimate torso widths and require either a side capture or calibrated
///    approximation before claiming a circumference.
/// 6. Attach confidence and always allow manual correction.
struct GuidedBodyScanService: BodyScanning {
    func scan() async throws -> BodyProfile {
        throw BodyScanError.unavailable
    }
}
