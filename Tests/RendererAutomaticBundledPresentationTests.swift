#if DEBUG
import Foundation
import Metal
import XCTest
@testable import FitCheck

@MainActor
final class RendererAutomaticBundledPresentationTests: XCTestCase {
    private let presentation = RendererPresentation(
        navigationTitle: "Illustrative 3D Preview", context: "Geometric Vest Concept · Navy · S",
        initialMaterial: .navy, allowsMaterialChanges: false,
        geometrySource: .bundled(.reviewedVest)
    )

    func testBundledProductAutomaticallyLoadsActualFileIntoMetalAndLocksSourceAndMaterial() async throws {
        let expected = try await RendererBundledAssetLoader().load(.reviewedVest)
        let model = RendererLabModel(presentation: presentation)
        defer { model.close() }
        let request = try XCTUnwrap(model.open(isActive: true))
        let scene = try XCTUnwrap(model.session)
        XCTAssertEqual(model.assetState, .loading)
        XCTAssertNil(scene.garment, "No temporary procedural shirt may appear under the vest title")
        await request.value
        XCTAssertEqual(model.assetState, .loaded)
        let garment = try XCTUnwrap(scene.garment)
        let vertexBuffer = try XCTUnwrap(garment.vertexBuffer)
        let indexBuffer = try XCTUnwrap(garment.indexBuffer)
        XCTAssertEqual(vertexBuffer.length, expected.mesh.vertices.count * MemoryLayout<RendererVertex>.stride)
        XCTAssertEqual(indexBuffer.length, expected.mesh.indices.count * MemoryLayout<UInt16>.stride)
        let vertices = vertexBuffer.contents().bindMemory(to: RendererVertex.self, capacity: expected.mesh.vertices.count)
        let indices = indexBuffer.contents().bindMemory(to: UInt16.self, capacity: expected.mesh.indices.count)
        for index in expected.mesh.vertices.indices {
            XCTAssertEqual(vertices[index].position, expected.mesh.vertices[index].position)
            XCTAssertEqual(vertices[index].normal, expected.mesh.vertices[index].normal)
        }
        for index in expected.mesh.indices.indices { XCTAssertEqual(indices[index], expected.mesh.indices[index]) }
        XCTAssertNotEqual(garment.mesh.vertices.map(\.position), RendererProceduralAssets.garment().vertices.map(\.position))
        XCTAssertEqual(scene.garmentAssetIdentifier, expected.descriptor.asset.assetID)
        model.selectMaterial(.sage)
        model.selectProceduralGarment()
        XCTAssertNil(model.selectBundledGarment())
        XCTAssertNil(model.checkIncompatibleGarment())
        XCTAssertTrue(scene.garment === garment)
        XCTAssertTrue(garment.vertexBuffer === vertexBuffer)
        XCTAssertEqual(garment.color, RendererProceduralAssets.color(for: .navy))
        model.rotate(horizontal: 0.8, vertical: 0.1)
        XCTAssertNotEqual(model.orbit, .initial)
        model.resetView()
        XCTAssertEqual(model.orbit, .initial)
        model.setGarmentVisible(false)
        XCTAssertFalse(garment.isEnabled)
        model.resetAppearance()
        XCTAssertTrue(garment.isEnabled)
        XCTAssertEqual(garment.color, RendererProceduralAssets.color(for: .navy))
        XCTAssertTrue(garment.vertexBuffer === vertexBuffer)
    }

    func testCloseAndReopenKeepsApprovedSourceAndReleasesEveryPreviousBuffer() async throws {
        let model = RendererLabModel(presentation: presentation)
        defer { model.close() }
        var previousID: UUID?
        var reference: RendererMesh?
        for _ in 0..<3 {
            try await XCTUnwrap(model.open(isActive: true)).value
            let scene = try XCTUnwrap(model.session)
            let garment = try XCTUnwrap(scene.garment)
            XCTAssertEqual(scene.garmentAssetIdentifier, RendererBundledAssetDescriptor.reviewedVest.asset.assetID)
            XCTAssertNotEqual(scene.id, previousID)
            if let reference {
                XCTAssertEqual(garment.mesh.vertices.map(\.position), reference.vertices.map(\.position))
                XCTAssertEqual(garment.mesh.indices, reference.indices)
            }
            reference = garment.mesh
            previousID = scene.id
            model.close()
            XCTAssertTrue(scene.isDisposed)
            XCTAssertNil(garment.vertexBuffer)
            XCTAssertNil(garment.indexBuffer)
            XCTAssertNil(model.session)
        }
    }

    func testMissingAndChangedFileFailWithoutProceduralFallbackAndRetryUsesSameApprovedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("R3MissingAsset-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let info: [String: String] = ["CFBundleIdentifier": "fitcheck.r3.missing", "CFBundlePackageType": "BNDL", "CFBundleName": "MissingFixture"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Info.plist"))
        let bundle = try XCTUnwrap(Bundle(url: root))
        let model = RendererLabModel(presentation: presentation, assetLoader: RendererBundledAssetLoader(bundle: bundle))
        defer { model.close() }
        try await XCTUnwrap(model.open(isActive: true)).value
        let scene = try XCTUnwrap(model.session)
        XCTAssertEqual(model.assetState, .failed(.missingResource))
        XCTAssertNotNil(scene.mannequin.vertexBuffer)
        XCTAssertNil(scene.garment)
        model.restoreGarment()
        XCTAssertNil(scene.garment, "Recovery cannot substitute a shirt")
        try await XCTUnwrap(model.retryGarmentLoad()).value
        XCTAssertEqual(model.assetState, .failed(.missingResource))
        let source = try XCTUnwrap(Bundle.main.url(forResource: "FitCheckGeometricVest", withExtension: "fitmesh", subdirectory: "FitCheckDevelopmentAssets"))
        let bytes = try Data(contentsOf: source)
        let folder = try XCTUnwrap(bundle.resourceURL).appendingPathComponent("FitCheckDevelopmentAssets")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("FitCheckGeometricVest.fitmesh")
        try (bytes + Data([0x20])).write(to: file)
        try await XCTUnwrap(model.retryGarmentLoad()).value
        XCTAssertEqual(model.assetState, .failed(.integrityMismatch))
        XCTAssertNil(scene.garment)
        XCTAssertNil(scene.garmentAssetIdentifier)
        try bytes.write(to: file)
        try await XCTUnwrap(model.retryGarmentLoad()).value
        XCTAssertEqual(model.assetState, .loaded)
        XCTAssertTrue(model.session === scene)
        XCTAssertEqual(scene.garmentAssetIdentifier, RendererBundledAssetDescriptor.reviewedVest.asset.assetID)
        XCTAssertEqual(scene.garment?.color, RendererProceduralAssets.color(for: .navy))
    }

    func testObsoleteAutomaticSuccessAndFailureCannotCrossProductOrSceneBoundaries() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        for obsoleteFails in [false, true] {
            let loader = R3DeferredGarmentLoader()
            let obsolete = RendererLabModel(presentation: presentation, assetLoader: loader)
            let oldTask = try XCTUnwrap(obsolete.open(isActive: true))
            await loader.waitForRequest(0)
            let oldScene = try XCTUnwrap(obsolete.session)
            obsolete.close()
            let replacement = RendererLabModel(presentation: RendererPresentation(
                navigationTitle: "Illustrative 3D Preview", context: "Everyday Tee · Navy · S",
                allowsMaterialChanges: false
            ))
            replacement.open(isActive: true)
            let scene = try XCTUnwrap(replacement.session)
            let shirt = try XCTUnwrap(scene.garment)
            if obsoleteFails { await loader.fail(0, error: .integrityMismatch) }
            else { await loader.succeed(0, with: loaded) }
            await oldTask.value
            XCTAssertTrue(oldScene.isDisposed)
            XCTAssertNil(obsolete.session)
            XCTAssertEqual(obsolete.state, .idle)
            XCTAssertTrue(replacement.session === scene)
            XCTAssertTrue(scene.garment === shirt)
            XCTAssertNil(scene.garmentAssetIdentifier)
            XCTAssertEqual(shirt.mesh.vertices.map(\.position), RendererProceduralAssets.garment().vertices.map(\.position))
            replacement.close()
        }
    }

    func testBackgroundDuringAutomaticLoadRejectsOldFailureAndRestoresOnlyCurrentVest() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let loader = R3DeferredGarmentLoader()
        let model = RendererLabModel(presentation: presentation, assetLoader: loader)
        defer { model.close() }
        let oldTask = try XCTUnwrap(model.open(isActive: true))
        await loader.waitForRequest(0)
        let oldScene = try XCTUnwrap(model.session)
        model.setActive(false)
        XCTAssertTrue(oldScene.isDisposed)
        let currentTask = try XCTUnwrap(model.open(isActive: true))
        await loader.waitForRequest(1)
        let currentScene = try XCTUnwrap(model.session)
        XCTAssertNotEqual(currentScene.id, oldScene.id)
        await loader.succeed(1, with: loaded)
        await currentTask.value
        await loader.fail(0, error: .unreadableResource)
        await oldTask.value
        XCTAssertEqual(model.assetState, .loaded)
        XCTAssertTrue(model.session === currentScene)
        XCTAssertEqual(currentScene.garmentAssetIdentifier, loaded.descriptor.asset.assetID)
        model.rotate(horizontal: 0.4, vertical: 0.1)
        model.setGarmentVisible(false)
        let orbit = model.orbit
        let garment = try XCTUnwrap(currentScene.garment)
        model.setActive(false)
        XCTAssertNil(garment.vertexBuffer)
        model.setActive(true)
        XCTAssertEqual(model.assetState, .loaded)
        XCTAssertEqual(model.orbit, orbit)
        XCTAssertEqual(model.session?.garmentAssetIdentifier, loaded.descriptor.asset.assetID)
        XCTAssertFalse(try XCTUnwrap(model.session?.garment).isEnabled)
    }

    func testProceduralProductMissingGarmentStillRestoresItsOriginalApprovedShirt() throws {
        let source = RendererPresentation(navigationTitle: "Illustrative 3D Preview", initialMaterial: .sage, allowsMaterialChanges: false)
        let model = RendererLabModel(presentation: source, makeScene: { try RendererSceneSession(garmentAsset: nil) })
        model.open(isActive: true)
        defer { model.close() }
        let scene = try XCTUnwrap(model.session)
        XCTAssertEqual(model.garmentFailure, .missingAsset)
        model.restoreGarment()
        let garment = try XCTUnwrap(scene.garment)
        XCTAssertNil(model.garmentFailure)
        XCTAssertEqual(garment.mesh.vertices.map(\.position), RendererProceduralAssets.garment().vertices.map(\.position))
        XCTAssertEqual(garment.color, RendererProceduralAssets.color(for: .sage))
        XCTAssertNil(scene.garmentAssetIdentifier)
    }
}

private actor R3DeferredGarmentLoader: RendererGarmentLoading {
    private var requests: [CheckedContinuation<RendererLoadedGarment, Error>] = []
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    func load(_ descriptor: RendererBundledAssetDescriptor) async throws -> RendererLoadedGarment {
        // Ignore cancellation deliberately; scene owners must reject stale results.
        try await withCheckedThrowingContinuation { continuation in
            let index = requests.count
            requests.append(continuation)
            for waiter in waiters.removeValue(forKey: index) ?? [] { waiter.resume() }
        }
    }
    func waitForRequest(_ index: Int) async {
        guard requests.count <= index else { return }
        await withCheckedContinuation { waiters[index, default: []].append($0) }
    }
    func succeed(_ index: Int, with loaded: RendererLoadedGarment) { requests[index].resume(returning: loaded) }
    func fail(_ index: Int, error: RendererAssetLoadFailure) { requests[index].resume(throwing: error) }
}
#endif
