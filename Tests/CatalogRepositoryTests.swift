#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

final class CatalogRepositoryTests: XCTestCase {
    private let everyday = CatalogProductID(retailerID: "sample-studio", productID: "everyday-tee")

    func testListingAndLookupUseStableScopedIdentityWithoutFabricatedMeasurements() async throws {
        let repository = OfflineCatalogRepository()
        guard case let .products(products) = try await repository.listProducts() else {
            return XCTFail("Expected the synthetic collection")
        }
        XCTAssertEqual(Set(products.map(\.id)), Set([
            everyday,
            CatalogProductID(retailerID: "sample-studio", productID: "weekend-tee"),
            CatalogProductID(retailerID: "sample-studio", productID: "archived-tee")
        ]))
        for product in products {
            let lookup = try await repository.product(id: product.id)
            XCTAssertEqual(lookup, .found(product))
            XCTAssertEqual(product.provenance.source, .synthetic)
            XCTAssertTrue(product.images.isEmpty)
            XCTAssertTrue(product.variants.allSatisfy { $0.finishedMeasurements == nil })
        }
        let otherRetailer = try await repository.product(id: CatalogProductID(retailerID: "another-retailer", productID: "everyday-tee"))
        XCTAssertEqual(otherRetailer, .notFound)
    }

    func testVariantSelectionHonorsColorSizeAvailabilityAndVariantPrice() async throws {
        let repository = OfflineCatalogRepository()
        guard case let .available(navy) = try await repository.variant(productID: everyday, colorID: "navy", sizeID: "medium"),
              case let .available(cream) = try await repository.variant(productID: everyday, colorID: "cream", sizeID: "medium") else {
            return XCTFail("Expected two synthetic selectable variants")
        }
        XCTAssertEqual(navy.id, "everyday-navy-medium")
        XCTAssertEqual(cream.id, "everyday-cream-medium")
        XCTAssertEqual(navy.price?.minorUnits, 1800)
        XCTAssertEqual(cream.price?.minorUnits, 2000)
        guard case let .unavailable(soldOut) = try await repository.variant(productID: everyday, colorID: "navy", sizeID: "large"),
              case let .unavailable(unknown) = try await repository.variant(productID: everyday, colorID: "cream", sizeID: "large") else {
            return XCTFail("Unavailable or unknown stock must not be selectable")
        }
        XCTAssertEqual(soldOut.availability, .outOfStock)
        XCTAssertEqual(unknown.availability, .unknown)
        let missingOption = try await repository.variant(productID: everyday, colorID: "missing", sizeID: "medium")
        XCTAssertEqual(missingOption, .notFound)
    }

    func testDiscontinuedProductRemainsInspectableButVariantUnavailable() async throws {
        let repository = OfflineCatalogRepository()
        let id = CatalogProductID(retailerID: "sample-studio", productID: "archived-tee")
        guard case let .found(product) = try await repository.product(id: id) else {
            return XCTFail("Product information should remain inspectable")
        }
        XCTAssertEqual(product.title, "Archive Tee")
        guard case let .unavailable(variant) = try await repository.variant(productID: id, colorID: "graphite", sizeID: "medium") else {
            return XCTFail("An archived option must not be purchasable")
        }
        XCTAssertEqual(variant.availability, .discontinued)
    }

    func testEmptyUnavailableAndMalformedSourcesRemainDifferent() async throws {
        let empty = OfflineCatalogRepository(data: Data(#"{"schemaVersion":1,"products":[]}"#.utf8))
        let listing = try await empty.listProducts()
        XCTAssertEqual(listing, .empty)
        let absent = try await empty.product(id: everyday)
        XCTAssertEqual(absent, .notFound)

        let unavailable = OfflineCatalogRepository(dataProvider: { throw CatalogRepositoryError.unavailable })
        let unavailableListing = try await unavailable.listProducts()
        let unavailableProduct = try await unavailable.product(id: everyday)
        let unavailableVariant = try await unavailable.variant(productID: everyday, colorID: "navy", sizeID: "medium")
        XCTAssertEqual(unavailableListing, .unavailable)
        XCTAssertEqual(unavailableProduct, .unavailable)
        XCTAssertEqual(unavailableVariant, .sourceUnavailable)

        for bytes in [Data("bad JSON".utf8), Data(#"{"schemaVersion":99,"newShape":true}"#.utf8)] {
            do {
                _ = try await OfflineCatalogRepository(data: bytes).listProducts()
                XCTFail("Malformed/unsupported data must not become an empty successful catalog")
            } catch {
                XCTAssertEqual(error as? CatalogRepositoryError, .invalidData)
            }
        }
    }

    func testDuplicateProductFeedFailsAsAWholeRatherThanSilentlyPickingOne() async throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: SyntheticCatalog.data) as? [String: Any])
        var products = try XCTUnwrap(object["products"] as? [[String: Any]])
        products.append(products[0])
        object["products"] = products
        let data = try JSONSerialization.data(withJSONObject: object)
        do {
            _ = try await OfflineCatalogRepository(data: data).product(id: everyday)
            XCTFail("Duplicate identity must reject the feed")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .invalidData)
        }
    }

    func testSourceFailureIsRetryableWithoutPoisoningOrInventingSnapshot() async throws {
        let source = RecoveringCatalogSource()
        let repository = OfflineCatalogRepository(dataProvider: { try source.read() })
        do {
            _ = try await repository.listProducts()
            XCTFail("Expected initial source failure")
        } catch {
            XCTAssertEqual(error as? CatalogRepositoryError, .failed)
        }
        guard case let .found(product) = try await repository.product(id: everyday) else {
            return XCTFail("Retry should load actual valid data")
        }
        XCTAssertEqual(product.id, everyday)
        XCTAssertEqual(product.title, "Everyday Tee")
    }
}

private final class RecoveringCatalogSource: @unchecked Sendable {
    private let lock = NSLock()
    private var firstRead = true

    func read() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        if firstRead {
            firstRead = false
            throw CocoaError(.fileReadNoPermission)
        }
        return SyntheticCatalog.data
    }
}
#endif
