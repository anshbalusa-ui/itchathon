import Foundation
import XCTest
@testable import FitCheck

final class AvatarFeatureIsolationTests: XCTestCase {
    func testPilotRequiresExplicitDebugLaunchOptIn() {
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: []), .legacy)
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["fitcheck-avatar-internal"]), .legacy)
        #if DEBUG
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-avatar-internal"]), .avatar)
        #else
        XCTAssertEqual(InternalDevelopmentRoute.resolve(arguments: ["-fitcheck-avatar-internal"]), .legacy)
        #endif
    }
}

#if DEBUG
@MainActor
final class AvatarPilotModelTests: XCTestCase {
    private func profile(status: AvatarEvidenceStatus = .awaitingReview) -> AvatarProfileRecord {
        AvatarProfileRecord(
            schemaVersion: 1,
            createdAt: Date(timeIntervalSince1970: 0),
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: status,
            modelAssetIdentifier: "synthetic-test-asset",
            normalizedShapeParameters: ["synthetic-control": 0.2]
        )
    }

    func testMissingIncompleteAndEligibleMetadataRemainDistinctWithoutRenderer() async {
        let repository = PilotTestRepository()
        let model = AvatarPilotModel(repository: repository)
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.createAvatar))

        await repository.save(profile())
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.incompleteProfile))

        await repository.save(profile(status: .usableForIllustrativePreview))
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.previewUnavailable))
    }

    func testCorruptionIncompatibilityAndStorageFailureHaveDifferentRecovery() async {
        let failures: [(Error, AvatarRecoveryReason)] = [
            (AvatarProfileStorageError.corruptedProfile, .corruptedProfile),
            (AvatarProfileStorageError.unsupportedSchema, .unsupportedSchema),
            (AvatarProfileStorageError.invalidProfile, .invalidProfile),
            (AvatarProfileStorageError.invalidPreviewEvidence, .invalidProfile),
            (CocoaError(.fileReadNoPermission), .storageUnavailable)
        ]
        for (error, reason) in failures {
            let repository = PilotTestRepository()
            await repository.setLoadError(error)
            let model = AvatarPilotModel(repository: repository)
            await model.refresh()
            XCTAssertEqual(model.state, .recovery(reason))
            XCTAssertFalse(model.isWorking)
        }
        XCTAssertFalse(AvatarRecoveryReason.storageUnavailable.allowsDeletion)
        XCTAssertTrue(AvatarRecoveryReason.unsupportedSchema.allowsDeletion)
    }

    func testRetryRecoversFromTemporaryStorageFailureWithoutDeletingProfile() async {
        let repository = PilotTestRepository(profile: profile())
        await repository.setLoadError(CocoaError(.fileReadNoPermission))
        let model = AvatarPilotModel(repository: repository)
        await model.refresh()
        XCTAssertEqual(model.state, .recovery(.storageUnavailable))
        await repository.setLoadError(nil)
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.incompleteProfile))
    }

    func testDeletionFailureDoesNotReportSuccessAndCanBeRetried() async {
        let repository = PilotTestRepository(profile: profile())
        let model = AvatarPilotModel(repository: repository)
        await model.refresh()
        await repository.setDeletionError(CocoaError(.fileWriteNoPermission))
        await model.deleteProfile()
        XCTAssertEqual(model.state, .recovery(.deletionFailed))
        XCTAssertFalse(model.isWorking)
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.incompleteProfile))

        await repository.setDeletionError(nil)
        await model.deleteProfile()
        XCTAssertEqual(model.state, .entry(.createAvatar))
        await model.refresh()
        XCTAssertEqual(model.state, .entry(.createAvatar))
    }
}

private actor PilotTestRepository: AvatarProfilePersisting {
    private var profile: AvatarProfileRecord?
    private var loadError: Error?
    private var deletionError: Error?

    init(profile: AvatarProfileRecord? = nil) { self.profile = profile }
    func setLoadError(_ error: Error?) { loadError = error }
    func setDeletionError(_ error: Error?) { deletionError = error }
    func load() throws -> AvatarProfileRecord? {
        if let loadError { throw loadError }
        return profile
    }
    func save(_ profile: AvatarProfileRecord) { self.profile = profile }
    func delete() throws {
        if let deletionError { throw deletionError }
        profile = nil
    }
}
#endif
