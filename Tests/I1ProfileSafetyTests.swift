import Foundation
import XCTest
@testable import FitCheck

final class I1ProfileSafetyTests: XCTestCase {
    func testDeleteCannotRecursivelyRemoveDirectorySwappedAfterKindCheck() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("I1ProfileSafetyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let profileURL = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let markerURL = profileURL.appendingPathComponent("keep")
        let markerBytes = Data("unrelated directory content".utf8)
        let replacement = DirectorySwapBeforeUnlink(
            targetURL: profileURL,
            markerURL: markerURL,
            markerBytes: markerBytes
        )
        let repository = AvatarProfileRepository(
            directoryURL: directory, removeFile: { try replacement.removeFile(at: $0) }
        )
        try await repository.save(AvatarProfileRecord(
            schemaVersion: AvatarProfileRecord.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 0),
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: .awaitingReview,
            modelAssetIdentifier: nil,
            normalizedShapeParameters: [:]
        ))

        do {
            try await repository.delete()
            XCTFail("A substituted directory must not be removed or reported as deleted")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSPOSIXErrorDomain)
        }

        XCTAssertTrue(replacement.didSwapToDirectory, "The filesystem race must actually be injected")
        XCTAssertEqual(try Data(contentsOf: markerURL), markerBytes)
    }

    func testSaveDoesNotFollowSymlinkCreatedAfterStagingCleanup() async throws {
        try await assertStagingCollisionIsPreserved(.symbolicLink)
    }

    func testSaveDoesNotRemoveOtherFileCreatedAfterStagingCleanup() async throws {
        try await assertStagingCollisionIsPreserved(.regularFile)
    }

    private func assertStagingCollisionIsPreserved(_ kind: StagingEntrySwap.Kind) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("I1StagingSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = AvatarProfileRecord(
            schemaVersion: 1, createdAt: Date(timeIntervalSince1970: 0),
            captureMethod: .lidarFrontAndSide, evidenceStatus: .awaitingReview,
            modelAssetIdentifier: nil, normalizedShapeParameters: [:]
        )
        let updated = AvatarProfileRecord(
            schemaVersion: 1, createdAt: Date(timeIntervalSince1970: 1),
            captureMethod: .lidarFrontAndSide, evidenceStatus: .awaitingReview,
            modelAssetIdentifier: nil, normalizedShapeParameters: [:]
        )
        let repository = AvatarProfileRepository(directoryURL: directory)
        try await repository.save(original)
        let profileURL = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let originalBytes = try Data(contentsOf: profileURL)
        let stagingURL = directory.appendingPathComponent(".fitcheck-avatar-profile.pending")
        let unrelatedURL = directory.appendingPathComponent("unrelated")
        let marker = Data("different owner's synthetic data".utf8)
        if case .symbolicLink = kind {
            try marker.write(to: unrelatedURL)
        }
        try Data("abandoned staging".utf8).write(to: stagingURL)
        let replacement = StagingEntrySwap(
            stagingURL: stagingURL, unrelatedURL: unrelatedURL, bytes: marker, kind: kind
        )
        let racingRepository = AvatarProfileRepository(
            directoryURL: directory, removeFile: { try replacement.removeFile(at: $0) }
        )
        do {
            try await racingRepository.save(updated)
            XCTFail("A staging collision must fail without publishing or overwriting another entry")
        } catch {
            XCTAssertTrue([NSCocoaErrorDomain, NSPOSIXErrorDomain].contains((error as NSError).domain))
        }
        XCTAssertTrue(replacement.didReplace, "The post-cleanup entry substitution must occur")
        XCTAssertEqual(try Data(contentsOf: profileURL), originalBytes)
        switch kind {
        case .symbolicLink:
            XCTAssertEqual(try Data(contentsOf: unrelatedURL), marker)
            XCTAssertEqual(
                try FileManager.default.destinationOfSymbolicLink(atPath: stagingURL.path),
                unrelatedURL.path
            )
        case .regularFile:
            XCTAssertEqual(try Data(contentsOf: stagingURL), marker)
        }

        // The test owns this replacement. Remove it explicitly, then prove a clean retry.
        try AvatarProfileRepository.unlinkFile(at: stagingURL)
        try await repository.save(updated)
        let recovered = try await repository.load()
        XCTAssertEqual(recovered, updated)
    }
}

private final class DirectorySwapBeforeUnlink: @unchecked Sendable {
    private let targetURL: URL
    private let markerURL: URL
    private let markerBytes: Data
    private(set) var didSwapToDirectory = false

    init(targetURL: URL, markerURL: URL, markerBytes: Data) {
        self.targetURL = targetURL
        self.markerURL = markerURL
        self.markerBytes = markerBytes
    }

    func removeFile(at url: URL) throws {
        if !didSwapToDirectory && url.standardizedFileURL == targetURL.standardizedFileURL {
            didSwapToDirectory = true
            try FileManager.default.removeItem(at: targetURL)
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: false)
            try markerBytes.write(to: markerURL)
        }
        try AvatarProfileRepository.unlinkFile(at: url)
    }
}

private final class StagingEntrySwap: @unchecked Sendable {
    enum Kind { case symbolicLink, regularFile }
    private let stagingURL: URL
    private let unrelatedURL: URL
    private let bytes: Data
    private let kind: Kind
    private(set) var didReplace = false

    init(stagingURL: URL, unrelatedURL: URL, bytes: Data, kind: Kind) {
        self.stagingURL = stagingURL
        self.unrelatedURL = unrelatedURL
        self.bytes = bytes
        self.kind = kind
    }

    func removeFile(at url: URL) throws {
        try AvatarProfileRepository.unlinkFile(at: url)
        guard !didReplace, url.standardizedFileURL == stagingURL.standardizedFileURL else { return }
        didReplace = true
        switch kind {
        case .symbolicLink:
            try FileManager.default.createSymbolicLink(at: stagingURL, withDestinationURL: unrelatedURL)
        case .regularFile:
            try bytes.write(to: stagingURL)
        }
    }
}
