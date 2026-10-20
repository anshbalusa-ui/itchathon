import Foundation
import XCTest
@testable import FitCheck

final class AvatarFoundationTests: XCTestCase {
    private func profile(
        status: AvatarEvidenceStatus = .awaitingReview,
        asset: String? = nil,
        shape: [String: Double] = [:],
        version: Int = AvatarProfileRecord.currentSchemaVersion
    ) -> AvatarProfileRecord {
        AvatarProfileRecord(
            schemaVersion: version,
            createdAt: Date(timeIntervalSince1970: 0),
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: status,
            modelAssetIdentifier: asset,
            normalizedShapeParameters: shape
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testMissingProfileShowsAvatarCreation() {
        XCTAssertEqual(AvatarEntryResolver.destination(for: nil), .createAvatar)
    }

    func testUnreviewedProfileCannotUnlockSavedAvatar() {
        let unreviewed = profile(status: .awaitingReview, asset: "avatar", shape: ["torso": 0.1])
        XCTAssertEqual(AvatarEntryResolver.destination(for: unreviewed), .createAvatar)
    }

    func testInvalidAndMissingAvatarParametersCannotUnlockSavedAvatar() {
        let invalid: [AvatarProfileRecord] = [
            profile(status: .usableForIllustrativePreview, asset: nil, shape: ["torso": 0.1]),
            profile(status: .usableForIllustrativePreview, asset: "avatar", shape: [:]),
            profile(status: .usableForIllustrativePreview, asset: "avatar", shape: ["torso": .nan]),
            profile(status: .usableForIllustrativePreview, asset: "avatar", shape: ["torso": 5]),
            profile(status: .usableForIllustrativePreview, asset: "avatar", shape: ["": 0.2]),
            profile(status: .usableForIllustrativePreview, asset: "avatar", shape: ["torso": 0.2], version: 2)
        ]
        for record in invalid {
            XCTAssertEqual(AvatarEntryResolver.destination(for: record), .createAvatar)
        }
    }

    func testReviewedDerivedProfileCanResolveSavedAvatarRoute() {
        let supported = profile(
            status: .usableForIllustrativePreview,
            asset: "licensed-base-mesh",
            shape: ["shoulderMorph": 0.15]
        )
        XCTAssertEqual(AvatarEntryResolver.destination(for: supported), .savedAvatar)
    }

    func testPersistRoundTripAndDelete() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AvatarProfileRepository(directoryURL: dir)
        XCTAssertNil(try store.load())

        // Synthetic derived parameters are only test fixtures, never customer scans.
        let record = profile(
            status: .usableForIllustrativePreview,
            asset: "test-only-mesh",
            shape: ["shoulderMorph": 0.15]
        )
        try store.save(record)
        XCTAssertEqual(try store.load(), record)
        try store.delete()
        XCTAssertNil(try store.load())
        try store.delete()
    }

    func testCorruptFileDoesNotTurnIntoReadyAvatar() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("fitcheck-avatar-profile.json")
        try Data("not json".utf8).write(to: file)
        let store = AvatarProfileRepository(directoryURL: dir)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? AvatarProfileStorageError, .corruptedProfile)
        }
    }

    func testUnsupportedSchemaCannotBeSaved() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AvatarProfileRepository(directoryURL: dir)
        XCTAssertThrowsError(try store.save(profile(version: 99))) { error in
            XCTAssertEqual(error as? AvatarProfileStorageError, .unsupportedSchema)
        }
        XCTAssertNil(try store.load())
    }

    func testFalseReadyDataCannotBeSaved() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AvatarProfileRepository(directoryURL: dir)
        let bogus = profile(status: .usableForIllustrativePreview, asset: "avatar")
        XCTAssertThrowsError(try store.save(bogus)) { error in
            XCTAssertEqual(error as? AvatarProfileStorageError, .invalidPreviewEvidence)
        }
    }
}
