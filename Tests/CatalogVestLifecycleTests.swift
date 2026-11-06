#if DEBUG
import XCTest
@testable import FitCheck

@MainActor
final class CatalogVestLifecycleTests: XCTestCase {
    private let vestID = CatalogProductID(retailerID: "sample-studio", productID: "geometric-vest")

    func testVestSelectionCarriesBundledGeometryContextAndRejectsLateSizeResponse() async throws {
        let product = try XCTUnwrap(
            CatalogDocument.decode(SyntheticCatalog.data).products.first { $0.id == vestID }
        )
        let repository = DeferredVestRepository(product: product)
        let detail = CatalogDetailViewModel(repository: repository, productID: vestID)
        await detail.loadIfNeeded()

        XCTAssertEqual(detail.selectedColorID, "navy")
        XCTAssertEqual(detail.previewEligibility, .unavailable(.selectVariant))

        let small = try XCTUnwrap(product.variants.first { $0.id == "geometric-vest-navy-small" })
        let medium = try XCTUnwrap(product.variants.first { $0.id == "geometric-vest-navy-medium" })
        let oldRequest = Task { await detail.selectSize("small") }
        await repository.waitForRequest(size: "small")
        let currentRequest = Task { await detail.selectSize("medium") }
        await repository.waitForRequest(size: "medium")

        detail.openPreview()
        XCTAssertNil(detail.presentedPreview, "A pending variant lookup cannot authorize the vest preview")

        await repository.release(size: "medium", with: .available(medium))
        await currentRequest.value
        detail.openPreview()
        let preview = try XCTUnwrap(detail.presentedPreview)
        XCTAssertEqual(preview.productID, vestID)
        XCTAssertEqual(preview.variantID, medium.id)
        XCTAssertEqual(preview.colorID, "navy")
        XCTAssertEqual(preview.sizeID, "medium")
        XCTAssertEqual(preview.colorName, "Navy")
        XCTAssertEqual(preview.sizeLabel, "M")
        XCTAssertEqual(preview.rendererPresentation.context, "Geometric Vest Concept · Navy · M")
        XCTAssertEqual(preview.rendererPresentation.initialMaterial, .navy)
        XCTAssertFalse(preview.rendererPresentation.allowsMaterialChanges)
        XCTAssertEqual(preview.rendererPresentation.geometrySource, .bundled(.reviewedVest))

        await repository.release(size: "small", with: .available(small))
        await oldRequest.value
        XCTAssertEqual(detail.selectedVariant, medium)
        XCTAssertEqual(detail.presentedPreview, preview)
        XCTAssertEqual(detail.previewEligibility, .eligible(preview))
    }
}

private actor DeferredVestRepository: CatalogRepository {
    private enum Size: String, Hashable { case small, medium }

    private let product: CatalogProduct
    private var pending: [Size: CheckedContinuation<CatalogVariantLookup, Never>] = [:]
    private var waiters: [Size: [CheckedContinuation<Void, Never>]] = [:]

    init(product: CatalogProduct) {
        self.product = product
    }

    func listProducts() async throws -> CatalogListing { .products([product]) }

    func product(id: CatalogProductID) async throws -> CatalogProductLookup {
        id == product.id ? .found(product) : .notFound
    }

    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup {
        guard let size = Size(rawValue: sizeID), productID == product.id, colorID == "navy" else {
            return .notFound
        }
        return await withCheckedContinuation { continuation in
            pending[size] = continuation
            let registeredWaiters = waiters.removeValue(forKey: size) ?? []
            registeredWaiters.forEach { $0.resume() }
        }
    }

    func waitForRequest(size sizeID: String) async {
        guard let size = Size(rawValue: sizeID) else { return }
        if pending[size] != nil { return }
        await withCheckedContinuation { continuation in
            waiters[size, default: []].append(continuation)
        }
    }

    func release(size sizeID: String, with result: CatalogVariantLookup) {
        guard let size = Size(rawValue: sizeID) else { return }
        pending.removeValue(forKey: size)?.resume(returning: result)
    }
}
#endif
