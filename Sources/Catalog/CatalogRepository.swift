#if DEBUG
import Foundation

enum CatalogListing: Equatable, Sendable {
    case products([CatalogProduct])
    case empty
    case unavailable
}

enum CatalogProductLookup: Equatable, Sendable {
    case found(CatalogProduct)
    case notFound
    case unavailable
}

enum CatalogVariantLookup: Equatable, Sendable {
    case available(CatalogVariant)
    case unavailable(CatalogVariant)
    case notFound
    case sourceUnavailable
}

enum CatalogRepositoryError: Error, Equatable, Sendable {
    case invalidData
    case unavailable
    case failed
}

/// Returns validated domain values, never wire DTOs or partially decoded feeds.
/// Listing order and option order are supplied by the source, not size-label inference.
protocol CatalogRepository: Sendable {
    func listProducts() async throws -> CatalogListing
    func product(id: CatalogProductID) async throws -> CatalogProductLookup
    func variant(productID: CatalogProductID, colorID: String, sizeID: String) async throws -> CatalogVariantLookup
}
#endif
