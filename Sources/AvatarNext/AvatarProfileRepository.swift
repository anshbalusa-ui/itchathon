import Darwin
import Foundation

protocol AvatarProfilePersisting: Sendable {
    func load() async throws -> AvatarProfileRecord?
    func save(_ profile: AvatarProfileRecord) async throws
    func delete() async throws
}

/// Local-only derived metadata; no CVPixelBuffer, photos, video or depth maps.
/// Designed so tests can use a temporary directory without touching user data.
actor AvatarProfileRepository: AvatarProfilePersisting {
    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private let fileURL: URL
    private let stagingURL: URL
    private let fileManager: FileManager

    init(
        directoryURL: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) {
        self.fileURL = directoryURL.appendingPathComponent("fitcheck-avatar-profile.json")
        self.stagingURL = directoryURL.appendingPathComponent(".fitcheck-avatar-profile.pending")
        self.fileManager = fileManager
    }

    func load() async throws -> AvatarProfileRecord? {
        // An interrupted save is never a profile and must not outlive recovery.
        try removeFileIfPresent(at: stagingURL)
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if Self.isMissingFile(error) {
                return nil
            }
            throw error
        }

        let header: SchemaHeader
        do {
            header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        } catch {
            throw AvatarProfileStorageError.corruptedProfile
        }
        guard header.schemaVersion == AvatarProfileRecord.currentSchemaVersion else {
            throw AvatarProfileStorageError.unsupportedSchema
        }

        let profile: AvatarProfileRecord
        do {
            profile = try JSONDecoder().decode(AvatarProfileRecord.self, from: data)
        } catch {
            throw AvatarProfileStorageError.corruptedProfile
        }
        if let validationError = profile.validationError {
            throw validationError
        }
        try excludeFromBackup(fileURL)
        return profile
    }

    func save(_ profile: AvatarProfileRecord) async throws {
        if let validationError = profile.validationError {
            throw validationError
        }
        let bytes = try JSONEncoder().encode(profile)
        try removeFileIfPresent(at: stagingURL)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Prepare metadata before publishing it. A failed replacement must leave
        // the previous profile intact, including if backup exclusion fails.
        do {
            try bytes.write(to: stagingURL, options: [.completeFileProtection])
            try excludeFromBackup(stagingURL)
            // Same-directory rename is atomic and preserves the staged protection
            // and backup attributes; no unprotected replacement window.
            guard Darwin.rename(stagingURL.path, fileURL.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try removeFileIfPresent(at: stagingURL)
            throw error
        }
    }

    func delete() async throws {
        try removeFileIfPresent(at: stagingURL)
        try removeFileIfPresent(at: fileURL)
    }

    private func removeFileIfPresent(at url: URL) throws {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                // Never recursively remove an unexpected directory at the file path.
                throw CocoaError(.fileWriteUnknown)
            }
            try fileManager.removeItem(at: url)
        } catch {
            if !Self.isMissingFile(error) {
                throw error
            }
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == CocoaError.fileNoSuchFile.rawValue
                || nsError.code == CocoaError.fileReadNoSuchFile.rawValue
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}
