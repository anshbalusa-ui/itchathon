#if DEBUG
import Foundation

/// Local immutable feed. A future authorized adapter implements CatalogRepository;
/// views do not know whether a validated snapshot came from local or remote data.
actor OfflineCatalogRepository: CatalogRepository {
    private struct Snapshot {
        let document: CatalogDocument
        let index: [CatalogProductID: Int]
    }

    private let dataProvider: @Sendable () throws -> Data
    private var snapshot: Snapshot?

    init() {
        dataProvider = { SyntheticCatalog.data }
    }

    init(data: Data) {
        dataProvider = { data }
    }

    init(dataProvider: @escaping @Sendable () throws -> Data) {
        self.dataProvider = dataProvider
    }

    func listProducts() async throws -> CatalogListing {
        do {
            let products = try load().document.products
            return products.isEmpty ? .empty : .products(products)
        } catch CatalogRepositoryError.unavailable {
            return .unavailable
        }
    }

    func product(id: CatalogProductID) async throws -> CatalogProductLookup {
        do {
            let value = try load()
            guard let index = value.index[id] else { return .notFound }
            return .found(value.document.products[index])
        } catch CatalogRepositoryError.unavailable {
            return .unavailable
        }
    }

    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup {
        switch try await product(id: productID) {
        case let .found(product):
            guard let variant = product.variants.first(where: { $0.colorID == colorID && $0.sizeID == sizeID }) else {
                return .notFound
            }
            return variant.availability == .available ? .available(variant) : .unavailable(variant)
        case .notFound:
            return .notFound
        case .unavailable:
            return .sourceUnavailable
        }
    }

    private func load() throws -> Snapshot {
        if let snapshot { return snapshot }
        let data: Data
        do { data = try dataProvider() }
        catch let error as CatalogRepositoryError { throw error }
        catch { throw CatalogRepositoryError.failed }
        let document: CatalogDocument
        do { document = try CatalogDocument.decode(data) }
        catch { throw CatalogRepositoryError.invalidData }
        var index: [CatalogProductID: Int] = [:]
        index.reserveCapacity(document.products.count)
        for (offset, product) in document.products.enumerated() { index[product.id] = offset }
        let loaded = Snapshot(document: document, index: index)
        snapshot = loaded
        return loaded
    }
}
#endif
