import Foundation

enum AvatarProfileStorageError: Error, Equatable {
    case unsupportedSchema
    case invalidPreviewEvidence
    case corruptedProfile
}

protocol AvatarProfilePersisting {
    func load() throws -> AvatarProfileRecord?
    func save(_ profile: AvatarProfileRecord) throws
    func delete() throws
}

/// Local-only derived metadata; no CVPixelBuffer, photos, video or depth maps.
/// Designed so tests can use a temporary directory without touching user data.
struct AvatarProfileRepository: AvatarProfilePersisting {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) {
        self.fileURL = directoryURL.appendingPathComponent("fitcheck-avatar-profile.json")
        self.fileManager = fileManager
    }

    func load() throws -> AvatarProfileRecord? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let profile: AvatarProfileRecord
        do {
            profile = try JSONDecoder().decode(AvatarProfileRecord.self, from: data)
        } catch {
            throw AvatarProfileStorageError.corruptedProfile
        }

        guard profile.schemaVersion == AvatarProfileRecord.currentSchemaVersion else {
            throw AvatarProfileStorageError.unsupportedSchema
        }
        guard profile.evidenceStatus != .usableForIllustrativePreview
                || profile.isUsableForIllustrativePreview else {
            throw AvatarProfileStorageError.invalidPreviewEvidence
        }
        return profile
    }

    func save(_ profile: AvatarProfileRecord) throws {
        guard profile.schemaVersion == AvatarProfileRecord.currentSchemaVersion else {
            throw AvatarProfileStorageError.unsupportedSchema
        }
        guard profile.evidenceStatus != .usableForIllustrativePreview
                || profile.isUsableForIllustrativePreview else {
            throw AvatarProfileStorageError.invalidPreviewEvidence
        }
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let bytes = try JSONEncoder().encode(profile)
        // Complete iOS file protection applies while the device is locked.
        try bytes.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func delete() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
