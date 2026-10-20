import Foundation
import XCTest
@testable import FitCheck

final class AvatarFoundationTests: XCTestCase {
    private func profile(
        status: AvatarEvidenceStatus = .awaitingReview,
        asset: String? = nil,
        shape: [String: Double] = [:],
        version: Int = AvatarProfileRecord.currentSchemaVersion,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> AvatarProfileRecord {
        AvatarProfileRecord(
            schemaVersion: version,
            createdAt: createdAt,
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: status,
            modelAssetIdentifier: asset,
            normalizedShapeParameters: shape
        )
    }

    func testMissingAndIncompleteProfilesHaveDistinctRoutes() {
        XCTAssertEqual(AvatarEntryResolver.destination(for: nil), .createAvatar)
        XCTAssertEqual(AvatarEntryResolver.destination(for: profile()), .incompleteProfile)
    }

    func testUnsupportedAndMalformedRecordsCannotUnlockSavedAvatar() {
        let valid = profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["torso": 0.1])
        let invalid: [AvatarProfileRecord] = [
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["torso": 0.1], version: 99),
            profile(status: .awaitingReview, asset: "synthetic", shape: ["torso": 2]),
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["": 0.1]),
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["torso": .infinity]),
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["torso": .nan]),
            profile(status: .usableForIllustrativePreview, asset: " ", shape: ["torso": 0.1]),
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: ["torso": 0.1],
                    createdAt: Date(timeIntervalSince1970: .infinity)),
            profile(status: .usableForIllustrativePreview, asset: nil, shape: ["torso": 0.1]),
            profile(status: .usableForIllustrativePreview, asset: "synthetic", shape: [:])
        ]
        XCTAssertEqual(AvatarEntryResolver.destination(for: valid), .previewUnavailable)
        for record in invalid {
            XCTAssertEqual(
                AvatarEntryResolver.destination(for: record, previewIsSupported: { _ in true }),
                .invalidProfile
            )
        }
        XCTAssertEqual(
            AvatarEntryResolver.destination(for: profile(), previewIsSupported: { _ in true }),
            .incompleteProfile
        )
    }

    func testCompatibilityCallbackGatesKnownSyntheticAssetAndControls() {
        let supported = profile(status: .usableForIllustrativePreview,
                                asset: "synthetic-mesh-v1", shape: ["torso": 0.1])
        let compatibility: (AvatarProfileRecord) -> Bool = {
            $0.modelAssetIdentifier == "synthetic-mesh-v1"
                && Set($0.normalizedShapeParameters.keys) == ["torso"]
        }
        XCTAssertEqual(
            AvatarEntryResolver.destination(for: supported, previewIsSupported: compatibility),
            .savedAvatar
        )
        let unknownAsset = profile(status: .usableForIllustrativePreview,
                                   asset: "arbitrary-string", shape: ["torso": 0.1])
        XCTAssertEqual(
            AvatarEntryResolver.destination(for: unknownAsset, previewIsSupported: compatibility),
            .previewUnavailable
        )
        let unknownControls = profile(status: .usableForIllustrativePreview,
                                      asset: "synthetic-mesh-v1", shape: ["futureControl": 0.1])
        XCTAssertEqual(
            AvatarEntryResolver.destination(for: unknownControls, previewIsSupported: compatibility),
            .previewUnavailable
        )
    }

}
