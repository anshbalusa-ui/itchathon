#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

@MainActor
final class CatalogBundledDataBoundaryTests: XCTestCase {
    private let vestID = CatalogProductID(retailerID: "sample-studio", productID: "geometric-vest")

    func testActualBundledPreviewsPreserveMissingPendingUnsupportedAndCorruptProfileStates() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = AvatarProfileRepository(directoryURL: directory)
        try await profiles.save(pendingProfile())
        let file = directory.appendingPathComponent("fitcheck-avatar-profile.json")
        let pendingBytes = try Data(contentsOf: file)
        try await profiles.delete()
        let future = Data(#"{"schemaVersion":99,"createdAt":0,"captureMethod":"lidarFrontAndSide","evidenceStatus":"usableForIllustrativePreview","modelAssetIdentifier":"synthetic","normalizedShapeParameters":{}}"#.utf8)
        let cases: [Data?] = [nil, pendingBytes, future, Data("not-json".utf8)]
        let pilot = AvatarPilotModel(repository: profiles)
        for (index, bytes) in cases.enumerated() {
            if let bytes { try bytes.write(to: file, options: .atomic) }
            await pilot.refresh()
            switch index {
            case 0: XCTAssertEqual(pilot.state, .entry(.createAvatar))
            case 1: XCTAssertEqual(pilot.state, .entry(.incompleteProfile))
            case 2: XCTAssertEqual(pilot.state, .recovery(.unsupportedSchema))
            default: XCTAssertEqual(pilot.state, .recovery(.corruptedProfile))
            }
            let originalState = pilot.state
            let detail = CatalogDetailViewModel(repository: OfflineCatalogRepository(), productID: vestID)
            await detail.loadIfNeeded()
            let small = try await renderSelectedVest(detail, size: "small")
            let medium = try await renderSelectedVest(detail, size: "medium")
            XCTAssertEqual(small.vertices.map(\.position), medium.vertices.map(\.position))
            XCTAssertEqual(small.vertices.map(\.normal), medium.vertices.map(\.normal))
            XCTAssertEqual(small.indices, medium.indices, "Size labels cannot fabricate size-specific geometry")
            await pilot.refresh()
            XCTAssertEqual(pilot.state, originalState)
            if let bytes { XCTAssertEqual(try Data(contentsOf: file), bytes) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        }
    }

    func testDeletingProtectedProfileDoesNotAffectIndependentFileBackedCatalogPreview() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = AvatarProfileRepository(directoryURL: directory)
        try await profiles.save(pendingProfile())
        let detail = CatalogDetailViewModel(repository: OfflineCatalogRepository(), productID: vestID)
        await detail.loadIfNeeded()
        let beforeDeletion = try await renderSelectedVest(detail, size: "small")
        try await profiles.delete()
        let afterDeletion = try await renderSelectedVest(detail, size: "medium")
        let profile = try await profiles.load()
        XCTAssertNil(profile)
        XCTAssertEqual(afterDeletion.vertices.map(\.position), beforeDeletion.vertices.map(\.position))
        XCTAssertEqual(afterDeletion.indices, beforeDeletion.indices)
        XCTAssertEqual(detail.selectedVariant?.id, "geometric-vest-navy-medium")
        XCTAssertNil(detail.selectedVariant?.price)
        XCTAssertNil(detail.selectedVariant?.finishedMeasurements)
    }

    private func renderSelectedVest(_ detail: CatalogDetailViewModel, size: String) async throws -> RendererMesh {
        await detail.selectSize(size)
        detail.openPreview()
        let preview = try XCTUnwrap(detail.presentedPreview)
        XCTAssertEqual(preview.productID, vestID)
        XCTAssertEqual(preview.variantID, "geometric-vest-navy-\(size)")
        XCTAssertEqual(preview.rendererPresentation.geometrySource, .bundled(.reviewedVest))
        let renderer = RendererLabModel(presentation: preview.rendererPresentation)
        defer {
            renderer.close()
            detail.dismissPreview()
        }
        try await XCTUnwrap(renderer.open(isActive: true)).value
        XCTAssertEqual(renderer.assetState, .loaded)
        let scene = try XCTUnwrap(renderer.session)
        XCTAssertEqual(scene.garmentAssetIdentifier, RendererBundledAssetDescriptor.reviewedVest.asset.assetID)
        let garment = try XCTUnwrap(scene.garment)
        XCTAssertEqual(garment.vertexBuffer?.length, garment.mesh.vertices.count * MemoryLayout<RendererVertex>.stride)
        XCTAssertEqual(garment.indexBuffer?.length, garment.mesh.indices.count * MemoryLayout<UInt16>.stride)
        return garment.mesh
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("R3ProfileBoundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pendingProfile() -> AvatarProfileRecord {
        AvatarProfileRecord(schemaVersion: AvatarProfileRecord.currentSchemaVersion,
                            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                            captureMethod: .lidarFrontAndSide, evidenceStatus: .awaitingReview,
                            modelAssetIdentifier: nil, normalizedShapeParameters: [:])
    }
}
#endif
