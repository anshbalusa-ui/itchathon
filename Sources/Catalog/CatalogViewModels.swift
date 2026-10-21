#if DEBUG
import Foundation
import Combine

@MainActor
final class CatalogRootViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([CatalogProduct])
        case empty
        case unavailable
        case failed
    }

    @Published private(set) var state: State = .loading
    let repository: any CatalogRepository

    private var requestGeneration = 0
    private var didStart = false

    init(repository: any CatalogRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await reload()
    }

    func reload() async {
        requestGeneration += 1
        let generation = requestGeneration
        state = .loading

        do {
            let listing = try await repository.listProducts()
            guard requestGeneration == generation else { return }
            switch listing {
            case .products(let products):
                state = products.isEmpty ? .empty : .loaded(products)
            case .empty:
                state = .empty
            case .unavailable:
                state = .unavailable
            }
        } catch let error as CatalogRepositoryError {
            guard requestGeneration == generation else { return }
            state = error == .unavailable ? .unavailable : .failed
        } catch {
            guard requestGeneration == generation else { return }
            state = .failed
        }
    }
}

@MainActor
final class CatalogDetailViewModel: ObservableObject {
    enum ProductState: Equatable {
        case loading
        case loaded(CatalogProduct)
        case notFound
        case unavailable
        case failed
    }

    enum VariantState: Equatable {
        case idle
        case loading
        case available(CatalogVariant)
        case unavailable(CatalogVariant)
        case notFound
        case sourceUnavailable
        case failed
    }

    @Published private(set) var productState: ProductState = .loading
    @Published private(set) var selectedColorID: String?
    @Published private(set) var selectedSizeID: String?
    @Published private(set) var pendingSizeID: String?
    @Published private(set) var variantState: VariantState = .idle

    let repository: any CatalogRepository
    let productID: CatalogProductID

    private var productRequestGeneration = 0
    private var variantRequestGeneration = 0
    private var didStart = false
    private var lastAttemptedSizeID: String?

    init(repository: any CatalogRepository, productID: CatalogProductID) {
        self.repository = repository
        self.productID = productID
    }

    var product: CatalogProduct? {
        guard case .loaded(let product) = productState else { return nil }
        return product
    }

    var selectedVariant: CatalogVariant? {
        guard case .available(let variant) = variantState,
              selectedSizeID == variant.sizeID,
              selectedColorID == variant.colorID else { return nil }
        return variant
    }

    func loadIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        await reload()
    }

    func reload() async {
        productRequestGeneration += 1
        let generation = productRequestGeneration
        invalidateVariantSelection()
        selectedColorID = nil
        productState = .loading

        do {
            let lookup = try await repository.product(id: productID)
            guard productRequestGeneration == generation else { return }
            switch lookup {
            case .found(let product):
                guard product.id == productID else {
                    productState = .failed
                    return
                }
                productState = .loaded(product)
                selectedColorID = product.colors.first?.id
            case .notFound:
                productState = .notFound
            case .unavailable:
                productState = .unavailable
            }
        } catch let error as CatalogRepositoryError {
            guard productRequestGeneration == generation else { return }
            productState = error == .unavailable ? .unavailable : .failed
        } catch {
            guard productRequestGeneration == generation else { return }
            productState = .failed
        }
    }

    func selectColor(_ colorID: String) {
        guard let product,
              product.colors.contains(where: { $0.id == colorID }),
              selectedColorID != colorID else { return }
        invalidateVariantSelection()
        selectedColorID = colorID
    }

    func availability(for sizeID: String) -> CatalogAvailability? {
        guard let selectedColorID else { return nil }
        return product?.variants.first(where: {
            $0.colorID == selectedColorID && $0.sizeID == sizeID
        })?.availability
    }

    func canSelectSize(_ sizeID: String) -> Bool {
        availability(for: sizeID) == .available
    }

    func selectSize(_ sizeID: String) async {
        guard let product, let colorID = selectedColorID else { return }

        variantRequestGeneration += 1
        let generation = variantRequestGeneration
        selectedSizeID = nil
        pendingSizeID = nil
        variantState = .idle
        lastAttemptedSizeID = nil

        guard product.sizes.contains(where: { $0.id == sizeID }) else {
            variantState = .notFound
            return
        }

        guard let listedVariant = product.variants.first(where: {
            $0.colorID == colorID && $0.sizeID == sizeID
        }) else {
            variantState = .notFound
            return
        }
        guard listedVariant.availability == .available else {
            variantState = .unavailable(listedVariant)
            return
        }

        pendingSizeID = sizeID
        variantState = .loading
        lastAttemptedSizeID = sizeID

        do {
            let lookup = try await repository.variant(
                productID: productID,
                colorID: colorID,
                sizeID: sizeID
            )
            guard variantRequestGeneration == generation,
                  selectedColorID == colorID,
                  self.product?.id == product.id else { return }
            pendingSizeID = nil
            apply(lookup, expectedVariantID: listedVariant.id)
        } catch let error as CatalogRepositoryError {
            guard variantRequestGeneration == generation,
                  selectedColorID == colorID,
                  self.product?.id == product.id else { return }
            pendingSizeID = nil
            selectedSizeID = nil
            variantState = error == .unavailable ? .sourceUnavailable : .failed
        } catch {
            guard variantRequestGeneration == generation,
                  selectedColorID == colorID,
                  self.product?.id == product.id else { return }
            pendingSizeID = nil
            selectedSizeID = nil
            variantState = .failed
        }
    }

    func retryVariantLookup() async {
        guard let sizeID = lastAttemptedSizeID else { return }
        await selectSize(sizeID)
    }

    private func apply(_ lookup: CatalogVariantLookup, expectedVariantID: String) {
        selectedSizeID = nil
        switch lookup {
        case .available(let variant):
            guard variant.id == expectedVariantID,
                  variant.colorID == selectedColorID,
                  variant.sizeID == lastAttemptedSizeID,
                  variant.availability == .available else {
                variantState = .notFound
                return
            }
            selectedSizeID = variant.sizeID
            variantState = .available(variant)
        case .unavailable(let variant):
            guard variant.id == expectedVariantID,
                  variant.colorID == selectedColorID,
                  variant.sizeID == lastAttemptedSizeID,
                  variant.availability != .available else {
                variantState = .notFound
                return
            }
            variantState = .unavailable(variant)
        case .notFound:
            variantState = .notFound
        case .sourceUnavailable:
            variantState = .sourceUnavailable
        }
    }

    private func invalidateVariantSelection() {
        variantRequestGeneration += 1
        selectedSizeID = nil
        pendingSizeID = nil
        lastAttemptedSizeID = nil
        variantState = .idle
    }
}
#endif
