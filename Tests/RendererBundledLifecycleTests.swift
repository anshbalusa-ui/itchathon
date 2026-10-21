#if DEBUG
import Combine
import Metal
import XCTest
@testable import FitCheck

@MainActor
final class RendererBundledLifecycleTests: XCTestCase {
    func testReviewedGeometryUploadsIntoActualBuffersAndReturnsToProcedural() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let scene = try RendererSceneSession()
        defer { scene.dispose() }
        let mannequinBuffer = try XCTUnwrap(scene.mannequin.vertexBuffer)
        let pipeline = try XCTUnwrap(scene.pipelineState)
        let orbit = RendererOrbit(yaw: 0.8, pitch: 0.1)
        scene.apply(orbit: orbit, appearance: RendererAppearance())
        let transform = scene.modelTransform
        try scene.installGarment(loaded)
        let imported = try XCTUnwrap(scene.garment)
        let vertices = try XCTUnwrap(imported.vertexBuffer)
        let indices = try XCTUnwrap(imported.indexBuffer)
        XCTAssertEqual(vertices.length, loaded.mesh.vertices.count * MemoryLayout<RendererVertex>.stride)
        XCTAssertEqual(indices.length, loaded.mesh.indices.count * MemoryLayout<UInt16>.stride)
        guard vertices.length >= MemoryLayout<RendererVertex>.stride,
              indices.length >= MemoryLayout<UInt16>.stride else {
            return XCTFail("Uploaded buffers must contain at least one complete element")
        }
        let first = vertices.contents().assumingMemoryBound(to: RendererVertex.self).pointee
        XCTAssertEqual(first.position, loaded.mesh.vertices[0].position)
        XCTAssertEqual(first.normal, loaded.mesh.vertices[0].normal)
        XCTAssertEqual(indices.contents().assumingMemoryBound(to: UInt16.self).pointee, loaded.mesh.indices[0])
        XCTAssertEqual(scene.garmentAssetIdentifier, loaded.descriptor.asset.assetID)
        XCTAssertTrue(scene.mannequin.vertexBuffer === mannequinBuffer)
        XCTAssertTrue(scene.pipelineState === pipeline)
        XCTAssertEqual(scene.modelTransform, transform)
        scene.apply(orbit: orbit, appearance: RendererAppearance(garmentVisible: false, material: .sage))
        XCTAssertTrue(imported.vertexBuffer === vertices)
        XCTAssertTrue(imported.indexBuffer === indices)
        XCTAssertFalse(imported.isEnabled)
        XCTAssertEqual(imported.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        try scene.replaceGarment(asset: .garmentFixture)
        XCTAssertEqual(scene.garment?.mesh.vertices.count, RendererProceduralAssets.garment().vertices.count)
        XCTAssertNil(imported.vertexBuffer)
        XCTAssertNil(imported.indexBuffer)
        XCTAssertNil(scene.garmentAssetIdentifier)
    }

    func testRepeatedInstallClearAndDisposeReleaseEveryImportedBuffer() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        for _ in 0..<8 {
            let scene = try RendererSceneSession()
            try scene.installGarment(loaded)
            let first = try XCTUnwrap(scene.garment)
            scene.clearGarment()
            XCTAssertNil(first.vertexBuffer)
            XCTAssertNil(first.indexBuffer)
            XCTAssertNil(scene.garment)
            try scene.installGarment(loaded)
            let replacement = try XCTUnwrap(scene.garment)
            XCTAssertFalse(first === replacement)
            scene.dispose()
            XCTAssertNil(replacement.vertexBuffer)
            XCTAssertNil(replacement.indexBuffer)
            XCTAssertNil(scene.mannequin.vertexBuffer)
            XCTAssertNil(scene.view.delegate)
            XCTAssertThrowsError(try scene.installGarment(loaded))
        }
    }

    func testLateLoadAfterCloseCannotReviveDisposedScene() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        let oldScene = try XCTUnwrap(model.session)
        let request = try XCTUnwrap(model.selectBundledGarment())
        await gate.waitForRequest()
        model.close()
        await gate.succeedNext(with: loaded)
        await request.value
        XCTAssertNil(model.session)
        XCTAssertTrue(oldScene.isDisposed)
        XCTAssertNil(oldScene.garment)
        XCTAssertEqual(model.assetState, .procedural)
        model.setActive(true)
        XCTAssertNil(model.session)
    }

    func testLateLoadCannotOverrideManualReturnToProcedural() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        defer { model.close() }
        let request = try XCTUnwrap(model.selectBundledGarment())
        await gate.waitForRequest()
        model.selectProceduralGarment()
        let procedural = try XCTUnwrap(model.session?.garment)
        await gate.succeedNext(with: loaded)
        await request.value
        XCTAssertEqual(model.assetState, .procedural)
        XCTAssertTrue(model.session?.garment === procedural)
        XCTAssertNotNil(procedural.vertexBuffer)
        XCTAssertNil(model.session?.garmentAssetIdentifier)
        XCTAssertEqual(model.session?.garment?.mesh.vertices.count, RendererProceduralAssets.garment().vertices.count)
    }

    func testBackgroundRejectsOldCompletionAndInstallsOnlyIntoCurrentScene() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        defer { model.close() }
        let oldRequest = try XCTUnwrap(model.selectBundledGarment())
        await gate.waitForRequest()
        let oldScene = try XCTUnwrap(model.session)
        model.setActive(false)
        model.setActive(true)
        let replacement = try XCTUnwrap(model.session)
        await gate.waitForRequest()
        await gate.succeedNext(with: loaded)
        await oldRequest.value
        XCTAssertNil(replacement.garment)
        XCTAssertTrue(oldScene.isDisposed)
        XCTAssertEqual(model.assetState, .loading)
        let ready = expectation(description: "Current background-replacement request installed")
        let observer = model.$assetState.filter { $0 == .loaded }.prefix(1).sink { _ in ready.fulfill() }
        defer { observer.cancel() }
        await gate.succeedNext(with: loaded)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(replacement.garmentAssetIdentifier, loaded.descriptor.asset.assetID)
        XCTAssertNil(oldScene.garment)
    }

    func testSceneRetryRejectsStaleLoadAndForegroundPreservesValidatedSource() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        defer { model.close() }
        model.rotate(horizontal: 0.6, vertical: 0.1)
        model.selectMaterial(.sage)
        let originalOrbit = model.orbit
        let oldRequest = try XCTUnwrap(model.selectBundledGarment())
        await gate.waitForRequest()
        let oldScene = try XCTUnwrap(model.session)
        model.retry()
        let retried = try XCTUnwrap(model.session)
        await gate.waitForRequest()
        await gate.succeedNext(with: loaded)
        await oldRequest.value
        XCTAssertNil(retried.garment)
        let ready = expectation(description: "Retry scene receives its own request")
        let observer = model.$assetState.filter { $0 == .loaded }.prefix(1).sink { _ in ready.fulfill() }
        defer { observer.cancel() }
        await gate.succeedNext(with: loaded)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertNotEqual(retried.id, oldScene.id)
        model.setActive(false)
        model.setActive(true)
        let resumed = try XCTUnwrap(model.session)
        XCTAssertEqual(model.assetState, .loaded)
        XCTAssertEqual(resumed.garmentAssetIdentifier, loaded.descriptor.asset.assetID)
        XCTAssertEqual(resumed.garment?.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        XCTAssertEqual(model.orbit, originalOrbit)
        XCTAssertEqual(resumed.modelTransform, retried.modelTransform)
        XCTAssertNil(retried.garment)
    }

    func testFailedExplicitReloadCannotResurrectOldCPUCacheOnForeground() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        defer { model.close() }
        let first = try XCTUnwrap(model.selectBundledGarment())
        await gate.waitForRequest()
        await gate.succeedNext(with: loaded)
        await first.value
        let reload = try XCTUnwrap(model.retryGarmentLoad())
        await gate.waitForRequest()
        await gate.failNext(.integrityMismatch)
        await reload.value
        XCTAssertEqual(model.assetState, .failed(.integrityMismatch))
        XCTAssertNil(model.session?.garment)
        model.setActive(false)
        model.setActive(true)
        XCTAssertNotEqual(model.assetState, .loaded, "An explicit failed reload invalidates the previous CPU cache")
        XCTAssertNil(model.session?.garment)
        if model.assetState == .loading {
            await gate.waitForRequest()
            let failed = expectation(description: "Foreground load failure stays explicit")
            let observer = model.$assetState.filter { $0 == .failed(.integrityMismatch) }.prefix(1).sink { _ in failed.fulfill() }
            defer { observer.cancel() }
            await gate.failNext(.integrityMismatch)
            await fulfillment(of: [failed], timeout: 5)
        }
    }

    func testDifferentResponseDescriptorCannotSubstituteAnApprovedButUnrequestedMesh() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        let gate = DeferredGarmentLoader()
        let model = RendererLabModel(assetLoader: gate)
        model.open(isActive: true)
        defer { model.close() }
        let request = try XCTUnwrap(model.checkIncompatibleGarment())
        await gate.waitForRequest()
        await gate.succeedNext(with: loaded)
        await request.value
        XCTAssertEqual(model.assetState, .failed(.unsupportedAsset))
        XCTAssertNil(model.session?.garment)
        XCTAssertNil(model.session?.garmentAssetIdentifier)
        XCTAssertNotNil(model.session?.mannequin.vertexBuffer)
    }

    func testRealIncompatibleDescriptorLeavesNoGarmentAndManualRecoveryWorks() async throws {
        let model = RendererLabModel()
        model.open(isActive: true)
        defer { model.close() }
        let request = try XCTUnwrap(model.checkIncompatibleGarment())
        await request.value
        let scene = try XCTUnwrap(model.session)
        XCTAssertEqual(model.assetState, .failed(.unsupportedAsset))
        XCTAssertNil(scene.garment)
        XCTAssertNotNil(scene.mannequin.vertexBuffer)
        let retry = try XCTUnwrap(model.retryGarmentLoad())
        await retry.value
        XCTAssertEqual(model.assetState, .failed(.unsupportedAsset))
        XCTAssertNil(scene.garment)
        model.selectProceduralGarment()
        XCTAssertEqual(model.assetState, .procedural)
        XCTAssertEqual(scene.garment?.mesh.vertices.count, RendererProceduralAssets.garment().vertices.count)
        XCTAssertNotNil(scene.garment?.vertexBuffer)
    }

    func testAllAuthorizedCatalogSKUsKeepProceduralBuffersAndRejectLabSelection() throws {
        let products = try CatalogDocument.decode(SyntheticCatalog.data).products
        let skus = ["everyday-navy-small", "everyday-navy-medium", "weekend-sage-small", "weekend-sage-medium"]
        for sku in skus {
            let product = try XCTUnwrap(products.first { $0.variants.contains { $0.id == sku } })
            let variant = try XCTUnwrap(product.variants.first { $0.id == sku })
            guard case .eligible(let preview) = CatalogPreviewAssociation().resolve(
                product: product, selectedVariant: variant, selectedColorID: variant.colorID, selectedSizeID: variant.sizeID
            ) else { return XCTFail("R1 SKU must remain eligible: \(sku)") }
            let model = RendererLabModel(presentation: preview.rendererPresentation)
            model.open(isActive: true)
            let scene = try XCTUnwrap(model.session)
            let garment = try XCTUnwrap(scene.garment)
            let buffer = garment.vertexBuffer
            XCTAssertNil(model.selectBundledGarment())
            XCTAssertNil(model.checkIncompatibleGarment())
            XCTAssertNil(model.retryGarmentLoad())
            XCTAssertTrue(scene.garment === garment)
            XCTAssertTrue(garment.vertexBuffer === buffer)
            XCTAssertNil(scene.garmentAssetIdentifier)
            XCTAssertEqual(garment.mesh.vertices.count, RendererProceduralAssets.garment().vertices.count)
            model.close()
        }
    }
}

private actor DeferredGarmentLoader: RendererGarmentLoading {
    private var completions: [CheckedContinuation<RendererLoadedGarment, Error>] = []
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var requests = 0
    private var observedRequests = 0

    func load(_ descriptor: RendererBundledAssetDescriptor) async throws -> RendererLoadedGarment {
        // Deliberately ignores cancellation: the presentation owner must reject late results.
        try await withCheckedThrowingContinuation { continuation in
            completions.append(continuation)
            requests += 1
            if !requestWaiters.isEmpty { requestWaiters.removeFirst().resume() }
        }
    }

    func waitForRequest() async {
        if requests > observedRequests {
            observedRequests += 1
            return
        }
        await withCheckedContinuation { requestWaiters.append($0) }
        observedRequests += 1
    }

    func succeedNext(with asset: RendererLoadedGarment) {
        completions.removeFirst().resume(returning: asset)
    }

    func failNext(_ error: RendererAssetLoadFailure) {
        completions.removeFirst().resume(throwing: error)
    }
}
#endif
