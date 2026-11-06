import Foundation

/// Metadata for an eventual scan-derived avatar, never raw camera imagery.
/// An avatar preview does not establish garment-fit accuracy.
enum AvatarCaptureMethod: String, Codable, Equatable, Sendable {
    case lidarFrontAndSide
}

enum AvatarEvidenceStatus: String, Codable, Equatable, Sendable {
    case awaitingReview
    case usableForIllustrativePreview
}

enum AvatarProfileStorageError: Error, Equatable, Sendable {
    case unsupportedSchema
    case invalidProfile
    case invalidPreviewEvidence
    case corruptedProfile
}

struct AvatarProfileRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let createdAt: Date
    let captureMethod: AvatarCaptureMethod
    let evidenceStatus: AvatarEvidenceStatus
    let modelAssetIdentifier: String?
    /// Normalized mesh controls. These are not measurements or fit probabilities.
    let normalizedShapeParameters: [String: Double]

    /// Structural eligibility only; says nothing about renderer compatibility or scan accuracy.
    var isUsableForIllustrativePreview: Bool {
        validationError == nil && evidenceStatus == .usableForIllustrativePreview
    }

    var validationError: AvatarProfileStorageError? {
        guard schemaVersion == Self.currentSchemaVersion else { return .unsupportedSchema }
        guard createdAt.timeIntervalSince1970.isFinite else { return .invalidProfile }
        if let modelAssetIdentifier,
           modelAssetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .invalidProfile
        }
        guard normalizedShapeParameters.allSatisfy({ key, value in
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.isFinite
                && (-1.0...1.0).contains(value)
        }) else {
            return .invalidProfile
        }
        if evidenceStatus == .usableForIllustrativePreview,
           (modelAssetIdentifier == nil || normalizedShapeParameters.isEmpty) {
            return .invalidPreviewEvidence
        }
        return nil
    }
}

/// This models entry navigation, not scan quality or fit confidence.
enum AvatarEntryDestination: Equatable, Sendable {
    case createAvatar
    case incompleteProfile
    case previewUnavailable
    case savedAvatar
    case invalidProfile
}

enum AvatarEntryResolver {
    static func destination(
        for profile: AvatarProfileRecord?,
        previewIsSupported: (AvatarProfileRecord) -> Bool = { _ in false }
    ) -> AvatarEntryDestination {
        guard let profile else { return .createAvatar }
        guard profile.validationError == nil else { return .invalidProfile }
        guard profile.evidenceStatus == .usableForIllustrativePreview else {
            return .incompleteProfile
        }
        return previewIsSupported(profile) ? .savedAvatar : .previewUnavailable
    }
}

