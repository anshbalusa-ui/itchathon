#if DEBUG
import XCTest
@testable import FitCheck

@MainActor
final class CatalogPresentationTests: XCTestCase {
    func testListingEmptyUnavailableAndFailureCanBeRetried() async {
        let product = makeProduct()
        let repository = ScriptedCatalogRepository(listings: [
            .success(.empty),
            .success(.unavailable),
            .failure(.unavailable),
            .failure(.failed),
            .success(.products([product]))
        ])
        let model = CatalogRootViewModel(repository: repository)

        await model.reload()
        XCTAssertEqual(model.state, .empty)

        await model.reload()
        XCTAssertEqual(model.state, .unavailable)

        await model.reload()
        XCTAssertEqual(model.state, .unavailable)

        await model.reload()
        XCTAssertEqual(model.state, .failed)
        await model.reload()
        XCTAssertEqual(model.state, .loaded([product]))
    }

    func testProductLookupNotFoundUnavailableAndFailureCanBeRetried() async {
        let product = makeProduct()
        let repository = ScriptedCatalogRepository(productLookups: [
            product.id: [
                .success(.notFound),
                .success(.unavailable),
                .failure(.unavailable),
                .failure(.invalidData),
                .success(.found(product))
            ]
        ])
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)

        await model.reload()
        XCTAssertEqual(model.productState, .notFound)

        await model.reload()
        XCTAssertEqual(model.productState, .unavailable)

        await model.reload()
        XCTAssertEqual(model.productState, .unavailable)

        await model.reload()
        XCTAssertEqual(model.productState, .failed)

        await model.reload()
        XCTAssertEqual(model.productState, .loaded(product))
        XCTAssertEqual(model.selectedColorID, "navy")
        XCTAssertNil(model.selectedSizeID)
    }

    func testLookupRejectsADifferentScopedProduct() async {
        let product = makeProduct()
        let requestedID = CatalogProductID(retailerID: "another-retailer", productID: product.id.productID)
        let repository = ScriptedCatalogRepository(productLookups: [requestedID: [.success(.found(product))]])
        let model = CatalogDetailViewModel(repository: repository, productID: requestedID)
        await model.reload()
        XCTAssertEqual(model.productState, .failed)
        XCTAssertNil(model.product)
        XCTAssertNil(model.selectedColorID)
    }

    func testMatchingOptionsDoNotAuthorizeAForeignVariantIdentity() async {
        let product = makeProduct()
        let foreignVariant = CatalogVariant(id: "another-products-sku", colorID: "navy", sizeID: "small",
            availability: .available, price: CatalogMoney(minorUnits: 1, currencyCode: "USD"), finishedMeasurements: nil)
        let repository = ScriptedCatalogRepository(
            productLookups: [product.id: [.success(.found(product))]],
            variantLookups: [VariantLookupKey(colorID: "navy", sizeID: "small"): [.success(.available(foreignVariant))]]
        )
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)
        await model.reload()
        await model.selectSize("small")
        XCTAssertEqual(model.variantState, .notFound)
        XCTAssertNil(model.selectedVariant)
        XCTAssertNil(model.selectedSizeID)
    }

    func testAvailableAndUnavailableSizeSelectionNeverKeepsAStaleVariant() async {
        let product = makeProduct()
        let navySmall = variant(in: product, colorID: "navy", sizeID: "small")
        let creamMedium = variant(in: product, colorID: "cream", sizeID: "medium", availability: .outOfStock)
        let repository = ScriptedCatalogRepository(
            productLookups: [product.id: [.success(.found(product))]],
            variantLookups: [
                VariantLookupKey(colorID: "navy", sizeID: "small"): [.success(.available(navySmall))],
                VariantLookupKey(colorID: "cream", sizeID: "medium"): [.success(.unavailable(creamMedium))]
            ]
        )
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)
        await model.reload()

        XCTAssertTrue(model.canSelectSize("small"))
        XCTAssertFalse(model.canSelectSize("large"))
        await model.selectSize("small")
        XCTAssertEqual(model.selectedSizeID, "small")
        XCTAssertEqual(model.selectedVariant, navySmall)

        await model.selectSize("large")
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)
        XCTAssertEqual(model.variantState, .unavailable(variant(in: product, colorID: "navy", sizeID: "large", price: nil)))

        model.selectColor("cream")
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)
        await model.selectSize("medium")
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)
        XCTAssertEqual(model.variantState, .unavailable(creamMedium))
    }

    func testVariantNotFoundAndSourceUnavailableRemainUnselectedAndCanRetry() async {
        let product = makeProduct()
        let noPrice = variant(in: product, colorID: "navy", sizeID: "small", price: nil)
        let repository = ScriptedCatalogRepository(
            productLookups: [product.id: [.success(.found(product))]],
            variantLookups: [
                VariantLookupKey(colorID: "navy", sizeID: "small"): [
                    .success(.notFound),
                    .success(.sourceUnavailable),
                    .failure(.unavailable),
                    .failure(.failed),
                    .success(.available(noPrice))
                ]
            ]
        )
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)
        await model.reload()

        await model.selectSize("small")
        XCTAssertEqual(model.variantState, .notFound)
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)

        await model.retryVariantLookup()
        XCTAssertEqual(model.variantState, .sourceUnavailable)
        XCTAssertNil(model.selectedSizeID)

        await model.retryVariantLookup()
        XCTAssertEqual(model.variantState, .sourceUnavailable)
        XCTAssertNil(model.selectedSizeID)

        await model.retryVariantLookup()
        XCTAssertEqual(model.variantState, .failed)
        XCTAssertNil(model.selectedSizeID)

        await model.retryVariantLookup()
        XCTAssertEqual(model.selectedSizeID, "small")
        XCTAssertNil(model.selectedVariant?.price)
        XCTAssertEqual(model.product?.price, CatalogMoney(minorUnits: 1_800, currencyCode: "USD"))
    }

    func testVariantErrorClearsOldSelectionAndRetryDoesNotInheritProductPrice() async {
        let product = makeProduct()
        let navySmall = variant(in: product, colorID: "navy", sizeID: "small")
        let navyMediumWithoutPrice = variant(in: product, colorID: "navy", sizeID: "medium", price: nil)
        let repository = ScriptedCatalogRepository(
            productLookups: [product.id: [.success(.found(product))]],
            variantLookups: [
                VariantLookupKey(colorID: "navy", sizeID: "small"): [.success(.available(navySmall))],
                VariantLookupKey(colorID: "navy", sizeID: "medium"): [
                    .failure(.failed),
                    .success(.available(navyMediumWithoutPrice))
                ]
            ]
        )
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)
        await model.reload()

        await model.selectSize("small")
        XCTAssertEqual(model.selectedVariant, navySmall)
        await model.selectSize("medium")
        XCTAssertEqual(model.variantState, .failed)
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)

        await model.retryVariantLookup()
        XCTAssertEqual(model.selectedSizeID, "medium")
        XCTAssertNil(model.selectedVariant?.price)
        XCTAssertEqual(model.product?.price, CatalogMoney(minorUnits: 1_800, currencyCode: "USD"))
    }

    func testColorChangeRejectsLateVariantCompletion() async {
        let product = makeProduct()
        let repository = DeferredVariantCatalogRepository(product: product)
        let model = CatalogDetailViewModel(repository: repository, productID: product.id)
        await model.reload()

        let oldRequest = Task { await model.selectSize("small") }
        let navySmallKey = VariantLookupKey(colorID: "navy", sizeID: "small")
        await repository.waitForRequest(navySmallKey)

        model.selectColor("cream")
        XCTAssertEqual(model.selectedColorID, "cream")
        XCTAssertNil(model.selectedSizeID)
        XCTAssertNil(model.selectedVariant)

        let currentRequest = Task { await model.selectSize("medium") }
        let creamMediumKey = VariantLookupKey(colorID: "cream", sizeID: "medium")
        await repository.waitForRequest(creamMediumKey)
        await repository.release(creamMediumKey, with: .available(variant(in: product, colorID: "cream", sizeID: "medium")))
        await currentRequest.value

        XCTAssertEqual(model.selectedColorID, "cream")
        XCTAssertEqual(model.selectedSizeID, "medium")
        XCTAssertEqual(model.selectedVariant?.colorID, "cream")
        XCTAssertEqual(model.selectedVariant?.sizeID, "medium")

        await repository.release(navySmallKey, with: .available(variant(in: product, colorID: "navy", sizeID: "small")))
        await oldRequest.value
        XCTAssertEqual(model.selectedColorID, "cream")
        XCTAssertEqual(model.selectedSizeID, "medium")
        XCTAssertEqual(model.selectedVariant?.colorID, "cream")
        XCTAssertEqual(model.selectedVariant?.sizeID, "medium")
    }
}

private struct VariantLookupKey: Hashable, Sendable {
    let colorID: String
    let sizeID: String
}

private actor ScriptedCatalogRepository: CatalogRepository {
    private var listings: [Result<CatalogListing, CatalogRepositoryError>]
    private var productLookups: [CatalogProductID: [Result<CatalogProductLookup, CatalogRepositoryError>]]
    private var variantLookups: [VariantLookupKey: [Result<CatalogVariantLookup, CatalogRepositoryError>]]

    init(
        listings: [Result<CatalogListing, CatalogRepositoryError>] = [],
        productLookups: [CatalogProductID: [Result<CatalogProductLookup, CatalogRepositoryError>]] = [:],
        variantLookups: [VariantLookupKey: [Result<CatalogVariantLookup, CatalogRepositoryError>]] = [:]
    ) {
        self.listings = listings
        self.productLookups = productLookups
        self.variantLookups = variantLookups
    }

    func listProducts() async throws -> CatalogListing {
        guard !listings.isEmpty else { throw CatalogRepositoryError.failed }
        return try listings.removeFirst().get()
    }

    func product(id: CatalogProductID) async throws -> CatalogProductLookup {
        guard var results = productLookups[id], !results.isEmpty else { throw CatalogRepositoryError.failed }
        let result = results.removeFirst()
        productLookups[id] = results
        return try result.get()
    }

    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup {
        let key = VariantLookupKey(colorID: colorID, sizeID: sizeID)
        guard var results = variantLookups[key], !results.isEmpty else { throw CatalogRepositoryError.failed }
        let result = results.removeFirst()
        variantLookups[key] = results
        return try result.get()
    }
}

private actor DeferredVariantCatalogRepository: CatalogRepository {
    private let product: CatalogProduct
    private var pending: [VariantLookupKey: CheckedContinuation<CatalogVariantLookup, Never>] = [:]
    private var requestWaiters: [VariantLookupKey: [CheckedContinuation<Void, Never>]] = [:]

    init(product: CatalogProduct) {
        self.product = product
    }

    func listProducts() async throws -> CatalogListing {
        .products([product])
    }

    func product(id: CatalogProductID) async throws -> CatalogProductLookup {
        id == product.id ? .found(product) : .notFound
    }

    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup {
        let key = VariantLookupKey(colorID: colorID, sizeID: sizeID)
        return await withCheckedContinuation { continuation in
            pending[key] = continuation
            let waiters = requestWaiters.removeValue(forKey: key) ?? []
            waiters.forEach { $0.resume() }
        }
    }

    func waitForRequest(_ key: VariantLookupKey) async {
        if pending[key] != nil { return }
        await withCheckedContinuation { continuation in
            requestWaiters[key, default: []].append(continuation)
        }
    }

    func release(_ key: VariantLookupKey, with result: CatalogVariantLookup) {
        pending.removeValue(forKey: key)?.resume(returning: result)
    }
}

private func makeProduct() -> CatalogProduct {
    let colors = [
        CatalogColor(id: "navy", name: "Navy", hex: "#112233"),
        CatalogColor(id: "cream", name: "Cream", hex: "#F4E7D8")
    ]
    let sizes = [
        CatalogSize(id: "small", label: "S"),
        CatalogSize(id: "medium", label: "M"),
        CatalogSize(id: "large", label: "L")
    ]
    let variants = [
        CatalogVariant(id: "navy-small", colorID: "navy", sizeID: "small", availability: .available, price: CatalogMoney(minorUnits: 1_800, currencyCode: "USD"), finishedMeasurements: nil),
        CatalogVariant(id: "navy-medium", colorID: "navy", sizeID: "medium", availability: .available, price: CatalogMoney(minorUnits: 1_800, currencyCode: "USD"), finishedMeasurements: nil),
        CatalogVariant(id: "navy-large", colorID: "navy", sizeID: "large", availability: .outOfStock, price: nil, finishedMeasurements: nil),
        CatalogVariant(id: "cream-small", colorID: "cream", sizeID: "small", availability: .outOfStock, price: nil, finishedMeasurements: nil),
        CatalogVariant(id: "cream-medium", colorID: "cream", sizeID: "medium", availability: .available, price: CatalogMoney(minorUnits: 2_000, currencyCode: "USD"), finishedMeasurements: nil),
        CatalogVariant(id: "cream-large", colorID: "cream", sizeID: "large", availability: .unknown, price: nil, finishedMeasurements: nil)
    ]
    return CatalogProduct(
        id: CatalogProductID(retailerID: "test-studio", productID: "sample-tee"),
        title: "Synthetic Test Tee",
        description: nil,
        category: .tshirt,
        colors: colors,
        sizes: sizes,
        variants: variants,
        images: [],
        price: CatalogMoney(minorUnits: 1_800, currencyCode: "USD"),
        provenance: CatalogProvenance(source: .synthetic, revision: "test-v1", reference: "isolated-test-fixture")
    )
}

private func variant(
    in product: CatalogProduct,
    colorID: String,
    sizeID: String,
    availability: CatalogAvailability? = nil,
    price: CatalogMoney? = CatalogMoney(minorUnits: 1_800, currencyCode: "USD")
) -> CatalogVariant {
    guard let variant = product.variants.first(where: { $0.colorID == colorID && $0.sizeID == sizeID }) else {
        fatalError("Test fixture is missing the requested variant")
    }
    return CatalogVariant(
        id: variant.id,
        colorID: colorID,
        sizeID: sizeID,
        availability: availability ?? variant.availability,
        price: price,
        finishedMeasurements: variant.finishedMeasurements
    )
}
#endif
