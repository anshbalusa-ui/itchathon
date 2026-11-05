#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

@MainActor
final class IntegrationBoundaryTests: XCTestCase {
    private let everyday = CatalogProductID(retailerID: "sample-studio", productID: "everyday-tee")

    func testCatalogLoadingAndSelectionPreserveProtectedProfileBytesAndMeaning() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = AvatarProfileRepository(directoryURL: directory)
        let profile = pendingProfile()
        try await profiles.save(profile)
        let profileURL = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let originalBytes = try Data(contentsOf: profileURL)

        let repository = OfflineCatalogRepository()
        let detail = CatalogDetailViewModel(repository: repository, productID: everyday)
        await detail.loadIfNeeded()
        XCTAssertEqual(detail.product?.id, everyday)
        let productLookup = try await repository.product(id: everyday)
        XCTAssertEqual(productLookup, .found(try XCTUnwrap(detail.product)))
        detail.selectColor("cream")
        XCTAssertEqual(detail.selectedColorID, "cream")
        await detail.selectSize("medium")
        XCTAssertEqual(detail.selectedVariant?.id, "everyday-cream-medium")
        detail.selectColor("navy")
        await detail.selectSize("small")
        try exerciseIllustrativePreview(detail)

        XCTAssertEqual(try Data(contentsOf: profileURL), originalBytes)
        let loadedProfile = try await profiles.load()
        XCTAssertEqual(loadedProfile, profile)
    }

    func testCatalogSourceErrorsAndProfileDeletionDoNotAlterCatalogLookupsOrSelection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = AvatarProfileRepository(directoryURL: directory)
        let profile = pendingProfile()
        try await profiles.save(profile)
        let profileURL = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let originalBytes = try Data(contentsOf: profileURL)

        let unavailable = OfflineCatalogRepository(dataProvider: { throw CatalogRepositoryError.unavailable })
        let failedDetail = CatalogDetailViewModel(repository: unavailable, productID: everyday)
        await failedDetail.loadIfNeeded()
        XCTAssertEqual(failedDetail.productState, .unavailable)
        XCTAssertEqual(try Data(contentsOf: profileURL), originalBytes)
        let loadedAfterSourceError = try await profiles.load()
        XCTAssertEqual(loadedAfterSourceError, profile)

        let catalog = OfflineCatalogRepository()
        let detail = CatalogDetailViewModel(repository: catalog, productID: everyday)
        await detail.loadIfNeeded()
        detail.selectColor("navy")
        await detail.selectSize("small")
        XCTAssertEqual(detail.selectedVariant?.id, "everyday-navy-small")
        try await profiles.delete()
        let deletedProfile = try await profiles.load()
        XCTAssertNil(deletedProfile)
        let lookupAfterDeletion = try await catalog.product(id: everyday)
        XCTAssertEqual(lookupAfterDeletion, .found(try XCTUnwrap(detail.product)))
        let variantAfterDeletion = try await catalog.variant(productID: everyday, colorID: "navy", sizeID: "small")
        XCTAssertEqual(variantAfterDeletion, .available(try XCTUnwrap(detail.selectedVariant)))
        XCTAssertEqual(detail.selectedVariant?.id, "everyday-navy-small")
    }

    func testCatalogAndIllustrativePreviewNeverUpgradeMissingPendingOrUnsupportedProfileReadiness() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = AvatarProfileRepository(directoryURL: directory)
        let pilot = AvatarPilotModel(repository: profiles)
        let catalog = OfflineCatalogRepository()
        let detail = CatalogDetailViewModel(repository: catalog, productID: everyday)

        await pilot.refresh()
        XCTAssertEqual(pilot.state, .entry(.createAvatar))
        await detail.loadIfNeeded()
        detail.selectColor("cream")
        await detail.selectSize("medium")
        XCTAssertEqual(detail.selectedVariant?.id, "everyday-cream-medium")
        detail.selectColor("navy")
        await detail.selectSize("small")
        try exerciseIllustrativePreview(detail)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .entry(.createAvatar))
        let profileAfterCatalog = try await profiles.load()
        XCTAssertNil(profileAfterCatalog)

        let pending = pendingProfile()
        try await profiles.save(pending)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .entry(.incompleteProfile))
        detail.selectColor("navy")
        await detail.selectSize("small")
        try exerciseIllustrativePreview(detail)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .entry(.incompleteProfile))
        let profileAfterPendingInteractions = try await profiles.load()
        XCTAssertEqual(profileAfterPendingInteractions, pending)

        let url = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let futureSchema = Data(#"{"schemaVersion":99,"createdAt":0,"captureMethod":"lidarFrontAndSide","evidenceStatus":"usableForIllustrativePreview","modelAssetIdentifier":"synthetic","normalizedShapeParameters":{"x":0.1}}"#.utf8)
        try futureSchema.write(to: url, options: .atomic)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .recovery(.unsupportedSchema))
        detail.selectColor("cream")
        await detail.selectSize("medium")
        detail.selectColor("navy")
        await detail.selectSize("small")
        try exerciseIllustrativePreview(detail)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .recovery(.unsupportedSchema))
        XCTAssertEqual(try Data(contentsOf: url), futureSchema)
        do {
            _ = try await profiles.load()
            XCTFail("Unsupported schema must remain distinguishable from a missing profile")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .unsupportedSchema)
        }
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: url, options: .atomic)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .recovery(.corruptedProfile))
        detail.selectColor("navy")
        await detail.selectSize("small")
        try exerciseIllustrativePreview(detail)
        await pilot.refresh()
        XCTAssertEqual(pilot.state, .recovery(.corruptedProfile))
        XCTAssertEqual(try Data(contentsOf: url), corruptBytes)
        do {
            _ = try await profiles.load()
            XCTFail("Corrupt profile must remain distinguishable from an unsupported schema")
        } catch let error as AvatarProfileStorageError {
            XCTAssertEqual(error, .corruptedProfile)
        }
    }

    private func exerciseIllustrativePreview(_ detail: CatalogDetailViewModel) throws {
        detail.openPreview()
        let preview = try XCTUnwrap(detail.presentedPreview)
        let renderer = RendererLabModel(presentation: preview.rendererPresentation)
        renderer.open(isActive: true)
        defer {
            renderer.close()
            detail.dismissPreview()
        }
        let scene = try XCTUnwrap(renderer.session)
        XCTAssertEqual(scene.garment?.color, SIMD4<Float>(0.12, 0.22, 0.42, 1))
        renderer.rotate(horizontal: 0.5, vertical: 0.1)
        renderer.setGarmentVisible(false)
        renderer.resetAppearance()
        XCTAssertTrue(try XCTUnwrap(scene.garment).isEnabled)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IntegrationBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pendingProfile() -> AvatarProfileRecord {
        AvatarProfileRecord(
            schemaVersion: AvatarProfileRecord.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            captureMethod: .lidarFrontAndSide,
            evidenceStatus: .awaitingReview,
            modelAssetIdentifier: nil,
            normalizedShapeParameters: [:]
        )
    }
}
#endif
