import Foundation

/// Metadata for an eventual scan-derived avatar, never raw camera imagery.
/// An avatar preview does not establish garment-fit accuracy.
enum AvatarCaptureMethod: String, Codable, Equatable {
    case lidarFrontAndSide
}

enum AvatarEvidenceStatus: String, Codable, Equatable {
    case awaitingReview
    case usableForIllustrativePreview
}

struct AvatarProfileRecord: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let captureMethod: AvatarCaptureMethod
    let evidenceStatus: AvatarEvidenceStatus
    let modelAssetIdentifier: String?
    /// Normalized mesh controls. These are not measurements or fit probabilities.
    let normalizedShapeParameters: [String: Double]

    var isUsableForIllustrativePreview: Bool {
        guard schemaVersion == Self.currentSchemaVersion,
              evidenceStatus == .usableForIllustrativePreview,
              let modelAssetIdentifier,
              !modelAssetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalizedShapeParameters.isEmpty else {
            return false
        }
        return normalizedShapeParameters.allSatisfy { key, value in
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.isFinite
                && (-1.0...1.0).contains(value)
        }
    }
}

/// This models *entry navigation*, not scan quality or fit confidence.
enum AvatarEntryDestination: Equatable {
    case createAvatar
    case savedAvatar
}

enum AvatarEntryResolver {
    static func destination(for profile: AvatarProfileRecord?) -> AvatarEntryDestination {
        profile?.isUsableForIllustrativePreview == true ? .savedAvatar : .createAvatar
    }
}
