import Foundation
import XCTest
@testable import FitCheck

final class AvatarProfileRepositoryTests: XCTestCase {
    private let filename = "fitcheck-avatar-profile.json"
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func profile(
        status: AvatarEvidenceStatus = .awaitingReview,
        asset: String? = nil,
        shape: [String: Double] = [:],
        version: Int = AvatarProfileRecord.currentSchemaVersion
    ) -> AvatarProfileRecord {
        AvatarProfileRecord(
            schemaVersion: version,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: status,
            modelAssetIdentifier: asset,
            normalizedShapeParameters: shape
        )
    }

    private func eligibleProfile() -> AvatarProfileRecord {
        profile(
            status: .usableForIllustrativePreview,
            asset: "synthetic-avatar-v1",
            shape: ["torso": 0.25, "shoulder": -0.1]
        )
    }

    private func makeRepository(in directory: URL) -> AvatarProfileRepository {
        AvatarProfileRepository(directoryURL: directory)
    }

    private func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    func testMissingLoadReturnsNil() async throws {
        let repository = makeRepository(in: try temporaryDirectory())
        let loaded = try await repository.load()
        XCTAssertNil(loaded)
    }

    func testPendingAndEligibleProfilesRoundTripAndReplace() async throws {
        let repository = makeRepository(in: try temporaryDirectory())
        let pending = profile(shape: ["synthetic-control": 0.5])
        let eligible = eligibleProfile()

        try await repository.save(pending)
        let loadedPending = try await repository.load()
        XCTAssertEqual(loadedPending, pending)
        try await repository.save(eligible)
        let loadedEligible = try await repository.load()
        XCTAssertEqual(loadedEligible, eligible)
    }

    func testInvalidAndUnsupportedReplacementPreserveExistingBytes() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let existing = profile(shape: ["control": 0.2])
        try await repository.save(existing)
        let path = fileURL(in: directory)
        let originalBytes = try Data(contentsOf: path)

        do {
            try await repository.save(profile(shape: [" ": .infinity]))
            XCTFail("Expected invalid profile rejection")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .invalidProfile)
        }
        do {
            try await repository.save(profile(version: 99))
            XCTFail("Expected unsupported schema rejection")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .unsupportedSchema)
        }
        XCTAssertEqual(try Data(contentsOf: path), originalBytes)
        let loaded = try await repository.load()
        XCTAssertEqual(loaded, existing)
    }

    func testMalformedPendingFileIsRejectedWithoutDeletingIt() async throws {
        let directory = try temporaryDirectory()
        let bytes = try JSONEncoder().encode(profile(shape: ["invalid-control": 5]))
        let path = fileURL(in: directory)
        try bytes.write(to: path)
        do {
            _ = try await makeRepository(in: directory).load()
            XCTFail("Expected malformed pending metadata to be rejected")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .invalidProfile)
        }
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testInterruptedSaveIsDiscardedOnReloadAndExplicitDeletion() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let committed = profile(shape: ["synthetic-control": 0.1])
        try await repository.save(committed)
        let staging = directory.appendingPathComponent(".fitcheck-avatar-profile.pending")
        let interrupted = try JSONEncoder().encode(eligibleProfile())
        try interrupted.write(to: staging)

        let reloaded = try await makeRepository(in: directory).load()
        XCTAssertEqual(reloaded, committed, "Unpublished metadata must never replace the last committed profile")
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))

        try interrupted.write(to: staging)
        try await repository.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        let afterDelete = try await repository.load()
        XCTAssertNil(afterDelete)
    }

    func testCorruptV1AndFutureChangedShapeAreClassifiedAndPreserved() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let path = fileURL(in: directory)

        let corruptV1 = Data("{\"schemaVersion\":1,\"createdAt\":\"invalid\"}".utf8)
        try corruptV1.write(to: path)
        do {
            _ = try await repository.load()
            XCTFail("Expected corrupt v1 rejection")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .corruptedProfile)
        }
        XCTAssertEqual(try Data(contentsOf: path), corruptV1)

        let future = Data("{\"schemaVersion\":2,\"newPayload\":{\"evidenceStatus\":\"futureCase\"}}".utf8)
        try future.write(to: path)
        do {
            _ = try await repository.load()
            XCTFail("Expected unsupported future schema")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .unsupportedSchema)
        }
        XCTAssertEqual(try Data(contentsOf: path), future)

        var unknownV1 = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any]
        )
        unknownV1["evidenceStatus"] = "futureCase"
        let unknownV1Bytes = try JSONSerialization.data(withJSONObject: unknownV1)
        try unknownV1Bytes.write(to: path)
        do {
            _ = try await repository.load()
            XCTFail("Expected unknown v1 enum rejection")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .corruptedProfile)
        }
        XCTAssertEqual(try Data(contentsOf: path), unknownV1Bytes)
    }

    func testDeleteIsIdempotentAndAllowsExplicitRecovery() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let path = fileURL(in: directory)

        try await repository.delete()
        try Data("corrupted profile".utf8).write(to: path)
        do {
            _ = try await repository.load()
            XCTFail("Expected corruption before explicit recovery")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .corruptedProfile)
        }
        try await repository.delete()
        try await repository.save(profile(shape: ["valid": 0.4]))
        try await repository.delete()
        try await repository.delete()
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        let afterDelete = try await repository.load()
        XCTAssertNil(afterDelete)
        try await repository.save(eligibleProfile())
        let recovered = try await repository.load()
        XCTAssertEqual(recovered, eligibleProfile())
    }

    func testDeleteDoesNotRemoveDirectoryAtPreviouslyUsedProfilePath() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let path = fileURL(in: directory)
        try await repository.save(profile(shape: ["synthetic": 0.1]))
        try await repository.delete()

        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        let marker = path.appendingPathComponent("keep")
        let bytes = Data("unrelated directory content".utf8)
        try bytes.write(to: marker)

        do {
            try await repository.delete()
            XCTFail("Expected deletion to refuse an unexpected directory")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteUnknown.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: marker), bytes)
    }

    func testDirectoryAndBlockedParentFailuresAreNotMissingOrCorruption() async throws {
        let directory = try temporaryDirectory()
        let pathThatIsDirectory = fileURL(in: directory)
        try FileManager.default.createDirectory(
            at: pathThatIsDirectory,
            withIntermediateDirectories: false
        )
        let repository = makeRepository(in: directory)
        do {
            _ = try await repository.load()
            XCTFail("Expected directory read failure")
        } catch let error as AvatarProfileStorageError {
            XCTFail("I/O failure was reclassified as storage error: \(error)")
        } catch {
            // A directory at the data-file path is a real I/O failure.
        }

        let blockedParent = directory.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blockedParent)
        let blockedRepository = makeRepository(in: blockedParent)
        do {
            try await blockedRepository.save(profile())
            XCTFail("Expected parent path failure")
        } catch let error as AvatarProfileStorageError {
            XCTFail("I/O failure was reclassified as storage error: \(error)")
        } catch {
            // Parent path cannot be created as a directory.
        }
    }

    func testProtectionAndBackupExclusionAttributesWhenAvailable() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        try await repository.save(profile(shape: ["synthetic": 0.1]))

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL(in: directory).path)
        if let protection = attributes[.protectionKey] as? FileProtectionType {
            XCTAssertEqual(protection, .complete)
        }
        let values = try fileURL(in: directory).resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testFailedAtomicReplacementPreservesExistingDirectoryAndCleansStaging() async throws {
        let directory = try temporaryDirectory()
        let destination = fileURL(in: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let unrelated = destination.appendingPathComponent("keep")
        let bytes = Data("unrelated data at unexpected destination".utf8)
        try bytes.write(to: unrelated)

        do {
            try await makeRepository(in: directory).save(eligibleProfile())
            XCTFail("Expected replacement to fail rather than replace a directory")
        } catch {
            XCTAssertFalse(error is AvatarProfileStorageError)
        }
        do {
            try await makeRepository(in: directory).delete()
            XCTFail("Expected deletion to refuse an unexpected directory")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteUnknown.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: unrelated), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [filename])
    }

    func testDeleteFailurePreservesProfileAndSurfacesIOError() async throws {
        let directory = try temporaryDirectory()
        let repository = makeRepository(in: directory)
        let saved = eligibleProfile()
        try await repository.save(saved)
        let failingRepository = AvatarProfileRepository(
            directoryURL: directory, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) }
        )
        do {
            try await failingRepository.delete()
            XCTFail("Expected deletion failure")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
        }
        let preserved = try await repository.load()
        XCTAssertEqual(preserved, saved)
    }

    @MainActor
    func testAvatarOperationsLeaveLegacyProfileStoreDataIntact() async throws {
        let suiteName = "avatar-repository-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let bodyData = try JSONEncoder().encode(BodyProfile(
            chestCircumference: 1.00,
            waistCircumference: 0.90,
            shoulderWidth: 0.46,
            torsoLength: 0.45
        ))
        let garmentData = try JSONEncoder().encode(
            GarmentProfile(name: "Synthetic garment", chestFlat: 0.60, shoulderWidth: 0.50, length: 0.72)
        )
        defaults.set(bodyData, forKey: "fitcheck.bodyProfile")
        defaults.set(garmentData, forKey: "fitcheck.currentGarment")

        let repository = makeRepository(in: try temporaryDirectory())
        try await repository.save(eligibleProfile())
        _ = try await repository.load()
        try await repository.delete()

        XCTAssertEqual(defaults.data(forKey: "fitcheck.bodyProfile"), bodyData)
        XCTAssertEqual(defaults.data(forKey: "fitcheck.currentGarment"), garmentData)
        XCTAssertEqual(ProfileStore(defaults: defaults).bodyProfile.chestCircumference, 1.00)
    }
}

