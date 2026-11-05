#if DEBUG
import XCTest
@testable import FitCheck

@MainActor
final class CatalogPreviewPresentationTests: XCTestCase {
    private let everyday = CatalogProductID(retailerID: "sample-studio", productID: "everyday-tee")
    private let weekend = CatalogProductID(retailerID: "sample-studio", productID: "weekend-tee")

    func testPreviewReopeningPreservesSelectionAndMissingPriceButNotOldSceneTransforms() async throws {
        let detail = CatalogDetailViewModel(repository: OfflineCatalogRepository(), productID: weekend)
        await detail.loadIfNeeded()
        await detail.selectSize("medium")
        let selection = try XCTUnwrap(detail.selectedVariant)
        XCTAssertNil(selection.price)
        XCTAssertNil(selection.finishedMeasurements)
        detail.openPreview()
        let preview = try XCTUnwrap(detail.presentedPreview)
        XCTAssertEqual(preview.productID, weekend)
        XCTAssertEqual(preview.variantID, "weekend-sage-medium")
        let renderer = RendererLabModel(presentation: preview.rendererPresentation)
        renderer.open(isActive: true)
        let scene = try XCTUnwrap(renderer.session)
        XCTAssertEqual(scene.garment?.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        renderer.rotate(horizontal: 0.8, vertical: 0.1)
        renderer.setGarmentVisible(false)
        renderer.close()
        detail.dismissPreview()
        XCTAssertTrue(scene.isDisposed)
        XCTAssertEqual(detail.selectedVariant, selection)
        XCTAssertNil(detail.presentedPreview)

        detail.openPreview()
        let reopened = RendererLabModel(presentation: try XCTUnwrap(detail.presentedPreview).rendererPresentation)
        reopened.open(isActive: true)
        defer { reopened.close() }
        XCTAssertNotEqual(reopened.session?.id, scene.id)
        XCTAssertEqual(reopened.orbit, .initial)
        XCTAssertTrue(try XCTUnwrap(reopened.session?.garment).isEnabled)
        XCTAssertEqual(reopened.session?.garment?.color, SIMD4<Float>(0.25, 0.40, 0.32, 1))
        XCTAssertEqual(detail.selectedVariant, selection)
    }

    func testSizeChangesInvalidateSnapshotWithoutChangingAnyGeometry() async throws {
        let detail = CatalogDetailViewModel(repository: OfflineCatalogRepository(), productID: everyday)
        await detail.loadIfNeeded()
        await detail.selectSize("small")
        detail.openPreview()
        let smallPreview = try XCTUnwrap(detail.presentedPreview)
        let smallRenderer = RendererLabModel(presentation: smallPreview.rendererPresentation)
        smallRenderer.open(isActive: true)
        defer { smallRenderer.close() }
        let smallMesh = try XCTUnwrap(smallRenderer.session?.garment).mesh

        await detail.selectSize("medium")
        XCTAssertNil(detail.presentedPreview)
        detail.openPreview()
        let mediumPreview = try XCTUnwrap(detail.presentedPreview)
        XCTAssertEqual(mediumPreview.variantID, "everyday-navy-medium")
        XCTAssertNotEqual(mediumPreview.id, smallPreview.id)
        let mediumRenderer = RendererLabModel(presentation: mediumPreview.rendererPresentation)
        mediumRenderer.open(isActive: true)
        defer { mediumRenderer.close() }
        let mediumMesh = try XCTUnwrap(mediumRenderer.session?.garment).mesh
        XCTAssertEqual(smallMesh.vertices.map(\.position), mediumMesh.vertices.map(\.position))
        XCTAssertEqual(smallMesh.vertices.map(\.normal), mediumMesh.vertices.map(\.normal))
        XCTAssertEqual(smallMesh.indices, mediumMesh.indices)
        XCTAssertNil(detail.selectedVariant?.finishedMeasurements)
    }

    func testChangingToUnsupportedCreamClearsPreviewAndNeverSubstitutesStone() async throws {
        let detail = CatalogDetailViewModel(repository: OfflineCatalogRepository(), productID: everyday)
        await detail.loadIfNeeded()
        await detail.selectSize("small")
        detail.openPreview()
        XCTAssertEqual(detail.presentedPreview?.variantID, "everyday-navy-small")
        detail.selectColor("cream")
        XCTAssertNil(detail.presentedPreview)
        XCTAssertEqual(detail.previewEligibility, .unavailable(.unsupportedColor))
        await detail.selectSize("medium")
        XCTAssertEqual(detail.selectedVariant?.id, "everyday-cream-medium")
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview)
        detail.selectColor("navy")
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview, "Changing color requires a newly checked variant")
        await detail.selectSize("medium")
        detail.openPreview()
        XCTAssertEqual(detail.presentedPreview?.variantID, "everyday-navy-medium")
    }

    func testLateSizeResponseCannotReplaceCurrentPreviewSKU() async throws {
        let product = try sample(everyday)
        let repository = PreviewDeferredRepository(product: product)
        let detail = CatalogDetailViewModel(repository: repository, productID: everyday)
        await detail.loadIfNeeded()
        let small = try variant(product, color: "navy", size: "small")
        let medium = try variant(product, color: "navy", size: "medium")
        let older = Task { await detail.selectSize("small") }
        await repository.waitForRequest(color: "navy", size: "small")
        let current = Task { await detail.selectSize("medium") }
        await repository.waitForRequest(color: "navy", size: "medium")
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview, "Pending lookups cannot authorize a preview")
        await repository.release(color: "navy", size: "medium", result: .available(medium))
        await current.value
        detail.openPreview()
        let snapshot = detail.presentedPreview
        await repository.release(color: "navy", size: "small", result: .available(small))
        await older.value
        XCTAssertEqual(detail.selectedVariant, medium)
        XCTAssertEqual(detail.presentedPreview, snapshot)
        XCTAssertEqual(detail.presentedPreview?.variantID, medium.id)
    }

    func testColorChangeAndReloadRejectDelayedPreviewAuthorization() async throws {
        let product = try sample(everyday)
        let repository = PreviewDeferredRepository(product: product)
        let detail = CatalogDetailViewModel(repository: repository, productID: everyday)
        await detail.loadIfNeeded()
        let navy = try variant(product, color: "navy", size: "small")
        let older = Task { await detail.selectSize("small") }
        await repository.waitForRequest(color: "navy", size: "small")
        detail.selectColor("cream")
        await repository.release(color: "navy", size: "small", result: .available(navy))
        await older.value
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview)
        XCTAssertEqual(detail.selectedColorID, "cream")
        XCTAssertNil(detail.selectedVariant)

        detail.selectColor("navy")
        let pending = Task { await detail.selectSize("small") }
        await repository.waitForRequest(color: "navy", size: "small")
        await detail.reload()
        await repository.release(color: "navy", size: "small", result: .available(navy))
        await pending.value
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview)
        XCTAssertNil(detail.selectedSizeID)
        XCTAssertEqual(detail.previewEligibility, .unavailable(.selectVariant))
    }

    func testRetryCannotAuthorizeForeignSKUAndReloadDismissesValidPreview() async throws {
        let product = try sample(everyday)
        let repository = PreviewDeferredRepository(product: product)
        let detail = CatalogDetailViewModel(repository: repository, productID: everyday)
        await detail.loadIfNeeded()
        let listed = try variant(product, color: "navy", size: "small")
        let foreign = CatalogVariant(id: "unrelated-sku", colorID: listed.colorID, sizeID: listed.sizeID,
                                     availability: .available, price: nil, finishedMeasurements: nil)
        let first = Task { await detail.selectSize("small") }
        await repository.waitForRequest(color: "navy", size: "small")
        await repository.release(color: "navy", size: "small", result: .available(foreign))
        await first.value
        detail.openPreview()
        XCTAssertNil(detail.presentedPreview)
        XCTAssertEqual(detail.variantState, .notFound)
        let retry = Task { await detail.retryVariantLookup() }
        await repository.waitForRequest(color: "navy", size: "small")
        await repository.release(color: "navy", size: "small", result: .available(listed))
        await retry.value
        detail.openPreview()
        XCTAssertEqual(detail.presentedPreview?.variantID, listed.id)
        await detail.reload()
        XCTAssertNil(detail.presentedPreview)
        XCTAssertNil(detail.selectedVariant)
    }

    func testSourceAvailabilityChangesCannotLeaveAnEarlierPreviewActive() async throws {
        let product = try sample(everyday)
        let listed = try variant(product, color: "navy", size: "small")
        for availability: CatalogAvailability in [.outOfStock, .unknown, .discontinued] {
            let repository = PreviewDeferredRepository(product: product)
            let detail = CatalogDetailViewModel(repository: repository, productID: everyday)
            await detail.loadIfNeeded()
            let first = Task { await detail.selectSize("small") }
            await repository.waitForRequest(color: "navy", size: "small")
            await repository.release(color: "navy", size: "small", result: .available(listed))
            await first.value
            detail.openPreview()
            XCTAssertEqual(detail.presentedPreview?.variantID, listed.id)
            let refresh = Task { await detail.selectSize("small") }
            await repository.waitForRequest(color: "navy", size: "small")
            XCTAssertNil(detail.presentedPreview)
            let unavailable = CatalogVariant(id: listed.id, colorID: listed.colorID, sizeID: listed.sizeID,
                availability: availability, price: listed.price, finishedMeasurements: nil)
            await repository.release(color: "navy", size: "small", result: .unavailable(unavailable))
            await refresh.value
            detail.openPreview()
            XCTAssertNil(detail.presentedPreview)
            XCTAssertNil(detail.selectedVariant)
            XCTAssertEqual(detail.variantState, .unavailable(unavailable))
        }
    }

    private func sample(_ id: CatalogProductID) throws -> CatalogProduct {
        try XCTUnwrap(CatalogDocument.decode(SyntheticCatalog.data).products.first { $0.id == id })
    }

    private func variant(_ product: CatalogProduct, color: String, size: String) throws -> CatalogVariant {
        try XCTUnwrap(product.variants.first { $0.colorID == color && $0.sizeID == size })
    }
}

private actor PreviewDeferredRepository: CatalogRepository {
    private struct Key: Hashable { let color: String; let size: String }
    private let product: CatalogProduct
    private var pending: [Key: CheckedContinuation<CatalogVariantLookup, Never>] = [:]
    private var waiters: [Key: [CheckedContinuation<Void, Never>]] = [:]

    init(product: CatalogProduct) { self.product = product }

    func listProducts() async throws -> CatalogListing { .products([product]) }
    func product(id: CatalogProductID) async throws -> CatalogProductLookup {
        id == product.id ? .found(product) : .notFound
    }
    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup {
        guard productID == product.id else { return .notFound }
        let key = Key(color: colorID, size: sizeID)
        return await withCheckedContinuation { continuation in
            pending[key] = continuation
            for waiter in waiters.removeValue(forKey: key) ?? [] { waiter.resume() }
        }
    }
    func waitForRequest(color: String, size: String) async {
        let key = Key(color: color, size: size)
        guard pending[key] == nil else { return }
        await withCheckedContinuation { waiters[key, default: []].append($0) }
    }
    func release(color: String, size: String, result: CatalogVariantLookup) {
        pending.removeValue(forKey: Key(color: color, size: size))?.resume(returning: result)
    }
}
#endif
