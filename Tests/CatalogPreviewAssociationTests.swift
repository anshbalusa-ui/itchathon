#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

final class CatalogPreviewAssociationTests: XCTestCase {
    private var products: [CatalogProduct] {
        get throws { try CatalogDocument.decode(SyntheticCatalog.data).products }
    }

    private func product(_ id: String, from products: [CatalogProduct]) -> CatalogProduct {
        products.first { $0.id.productID == id }!
    }

    private func resolve(_ product: CatalogProduct, variantID: String? = nil, color: String? = nil, size: String? = nil,
                         association: CatalogPreviewAssociation = .init()) -> CatalogPreviewEligibility {
        let variant = variantID.flatMap { id in product.variants.first { $0.id == id } }
        return association.resolve(product: product, selectedVariant: variant,
                                  selectedColorID: color ?? variant?.colorID,
                                  selectedSizeID: size ?? variant?.sizeID)
    }

    func testFourApprovedSKUsShareOneUnscopedFixtureAcrossSizes() throws {
        let source = try products
        let cases: [(String, String, String, RendererMaterial)] = [
            ("everyday-tee", "everyday-navy-small", "small", .navy),
            ("everyday-tee", "everyday-navy-medium", "medium", .navy),
            ("weekend-tee", "weekend-sage-small", "small", .sage),
            ("weekend-tee", "weekend-sage-medium", "medium", .sage)
        ]
        var previews: [CatalogIllustrativePreview] = []
        for (productID, sku, size, material) in cases {
            let item = product(productID, from: source)
            guard case let .eligible(preview) = resolve(item, variantID: sku) else {
                return XCTFail("Expected approved SKU \(sku)")
            }
            XCTAssertEqual(preview.productID, item.id)
            XCTAssertEqual(preview.variantID, sku)
            XCTAssertEqual(preview.sizeID, size)
            XCTAssertEqual(preview.rendererPresentation.initialMaterial, material)
            XCTAssertFalse(preview.rendererPresentation.allowsMaterialChanges)
            previews.append(preview)
        }
        XCTAssertEqual(Set(previews.map(\.sizeID)), ["small", "medium"])
        XCTAssertNil(RendererAssetDescriptor.garmentFixture.productID)
        XCTAssertNil(RendererAssetDescriptor.garmentFixture.variantID)
    }

    func testSelectionMustBelongToExactScopedProductAndSKU() throws {
        let source = try products
        let everyday = product("everyday-tee", from: source)
        let weekend = product("weekend-tee", from: source)
        XCTAssertEqual(resolve(everyday, variantID: "everyday-navy-small", color: "sage", size: "small"), .unavailable(.unsupportedColor))
        let wrongRetailer = CatalogProduct(
            id: CatalogProductID(retailerID: "other-shop", productID: everyday.id.productID), title: everyday.title,
            description: everyday.description, category: everyday.category, colors: everyday.colors, sizes: everyday.sizes,
            variants: everyday.variants, images: everyday.images, price: everyday.price, provenance: everyday.provenance
        )
        XCTAssertEqual(resolve(wrongRetailer, variantID: "everyday-navy-small"), .unavailable(.unsupportedProduct))
        XCTAssertEqual(CatalogPreviewAssociation().resolve(
            product: weekend, selectedVariant: everyday.variants.first { $0.id == "everyday-navy-small" },
            selectedColorID: "sage", selectedSizeID: "small"
        ), .unavailable(.invalidSelection))
        let foreign = CatalogVariant(id: "foreign-sku", colorID: "navy", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil)
        let foreignProduct = CatalogProduct(
            id: everyday.id, title: everyday.title, description: everyday.description, category: everyday.category,
            colors: everyday.colors, sizes: everyday.sizes,
            variants: everyday.variants.map { $0.id == "everyday-navy-small" ? foreign : $0 }, images: everyday.images,
            price: everyday.price, provenance: everyday.provenance
        )
        XCTAssertEqual(resolve(foreignProduct, variantID: "foreign-sku"), .unavailable(.variantUnavailable))
    }

    func testSyntheticProvenanceAndUnsupportedCreamAreDenied() throws {
        let everyday = product("everyday-tee", from: try products)
        for provenance in [
            CatalogProvenance(source: .retailerProvided, revision: "sample-v1", reference: "local-synthetic-fixture"),
            CatalogProvenance(source: .synthetic, revision: "other", reference: "local-synthetic-fixture"),
            CatalogProvenance(source: .synthetic, revision: "sample-v1", reference: "other")
        ] {
            let changed = CatalogProduct(id: everyday.id, title: everyday.title, description: everyday.description,
                category: everyday.category, colors: everyday.colors, sizes: everyday.sizes, variants: everyday.variants,
                images: everyday.images, price: everyday.price, provenance: provenance)
            XCTAssertEqual(resolve(changed, variantID: "everyday-navy-small"), .unavailable(.unverifiedSource))
        }
        XCTAssertEqual(resolve(everyday, variantID: "everyday-cream-medium", color: "cream", size: "medium"), .unavailable(.unsupportedColor))
    }

    func testUnavailableAndUnknownVariantsDoNotPreview() throws {
        let archive = product("archived-tee", from: try products)
        XCTAssertEqual(resolve(archive, variantID: "archive-graphite-medium"), .unavailable(.unsupportedProduct))
        let everyday = product("everyday-tee", from: try products)
        for availability: CatalogAvailability in [.outOfStock, .unknown, .discontinued] {
            let original = everyday.variants.first { $0.id == "everyday-navy-small" }!
            let changedVariant = CatalogVariant(id: original.id, colorID: original.colorID, sizeID: original.sizeID,
                availability: availability, price: original.price, finishedMeasurements: original.finishedMeasurements)
            let changed = CatalogProduct(id: everyday.id, title: everyday.title, description: everyday.description,
                category: everyday.category, colors: everyday.colors, sizes: everyday.sizes,
                variants: everyday.variants.map { $0.id == original.id ? changedVariant : $0 }, images: everyday.images,
                price: everyday.price, provenance: everyday.provenance)
            XCTAssertEqual(resolve(changed, variantID: original.id), .unavailable(.variantUnavailable))
        }
    }

    func testUnrelatedIdentityAndReinterpretedColorsCannotBorrowTheFixture() throws {
        let everyday = product("everyday-tee", from: try products)
        let unrelated = CatalogProduct(
            id: .init(retailerID: everyday.id.retailerID, productID: "unrelated-tee"), title: everyday.title,
            description: everyday.description, category: everyday.category, colors: everyday.colors, sizes: everyday.sizes,
            variants: everyday.variants, images: everyday.images, price: everyday.price, provenance: everyday.provenance
        )
        XCTAssertEqual(resolve(unrelated, variantID: "everyday-navy-small"), .unavailable(.unsupportedProduct))
        for replacement in [
            CatalogColor(id: "navy", name: "Cream", hex: "#24364B"),
            CatalogColor(id: "navy", name: "Navy", hex: "#E8E0CC")
        ] {
            let recolored = CatalogProduct(
                id: everyday.id, title: everyday.title, description: everyday.description, category: everyday.category,
                colors: everyday.colors.map { $0.id == "navy" ? replacement : $0 }, sizes: everyday.sizes,
                variants: everyday.variants, images: everyday.images, price: everyday.price, provenance: everyday.provenance
            )
            XCTAssertEqual(resolve(recolored, variantID: "everyday-navy-small"), .unavailable(.unsupportedColor))
        }
    }

    func testSelectedResponseMustMatchSKUOptionsAndAvailabilityWithoutRequiringPriceEquality() throws {
        let everyday = product("everyday-tee", from: try products)
        let selected = everyday.variants.first { $0.id == "everyday-navy-small" }!
        let association = CatalogPreviewAssociation()
        for response in [
            CatalogVariant(id: "foreign-sku", colorID: "navy", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "cream", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "navy", sizeID: "medium", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "navy", sizeID: "small", availability: .unknown, price: nil, finishedMeasurements: nil)
        ] {
            XCTAssertEqual(association.resolve(product: everyday, selectedVariant: response, selectedColorID: "navy", selectedSizeID: "small"),
                           .unavailable(.invalidSelection))
        }
        XCTAssertEqual(association.resolve(product: everyday, selectedVariant: nil, selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.selectVariant))
        let missingPrice = CatalogVariant(id: selected.id, colorID: selected.colorID, sizeID: selected.sizeID,
                                         availability: .available, price: nil, finishedMeasurements: nil)
        guard case .eligible = association.resolve(product: everyday, selectedVariant: missingPrice, selectedColorID: "navy", selectedSizeID: "small") else {
            return XCTFail("A missing price does not change illustrative asset identity or create a price")
        }
    }

    func testFixtureMustPassExistingGarmentValidation() throws {
        let everyday = product("everyday-tee", from: try products)
        XCTAssertEqual(resolve(everyday, variantID: "everyday-navy-small", association: .init(fixture: nil)), .unavailable(.incompatibleFixture))
        let descriptor = RendererAssetDescriptor.garmentFixture
        let invalid: [RendererAssetDescriptor] = [
            .init(type: descriptor.type, role: .mannequin, schemaVersion: descriptor.schemaVersion, assetID: descriptor.assetID,
                  revision: descriptor.revision, coordinateSystem: descriptor.coordinateSystem, unit: descriptor.unit, origin: descriptor.origin,
                  scale: descriptor.scale, source: descriptor.source, provenance: descriptor.provenance, license: descriptor.license,
                  isLocallyOwned: descriptor.isLocallyOwned, productID: nil, variantID: nil, materialModel: descriptor.materialModel,
                  rendererCapability: descriptor.rendererCapability, personalized: descriptor.personalized),
            .init(type: descriptor.type, role: descriptor.role, schemaVersion: descriptor.schemaVersion, assetID: descriptor.assetID,
                  revision: 2, coordinateSystem: descriptor.coordinateSystem, unit: descriptor.unit, origin: descriptor.origin,
                  scale: descriptor.scale, source: descriptor.source, provenance: descriptor.provenance, license: descriptor.license,
                  isLocallyOwned: descriptor.isLocallyOwned, productID: nil, variantID: nil, materialModel: descriptor.materialModel,
                  rendererCapability: descriptor.rendererCapability, personalized: descriptor.personalized),
            .init(type: descriptor.type, role: descriptor.role, schemaVersion: descriptor.schemaVersion, assetID: descriptor.assetID,
                  revision: descriptor.revision, coordinateSystem: descriptor.coordinateSystem, unit: descriptor.unit, origin: descriptor.origin,
                  scale: descriptor.scale, source: descriptor.source, provenance: descriptor.provenance, license: descriptor.license,
                  isLocallyOwned: descriptor.isLocallyOwned, productID: nil, variantID: nil, materialModel: descriptor.materialModel,
                  rendererCapability: "unsupported", personalized: descriptor.personalized),
            .init(type: descriptor.type, role: descriptor.role, schemaVersion: descriptor.schemaVersion, assetID: descriptor.assetID,
                  revision: descriptor.revision, coordinateSystem: descriptor.coordinateSystem, unit: descriptor.unit, origin: descriptor.origin,
                  scale: descriptor.scale, source: descriptor.source, provenance: descriptor.provenance, license: .commercial,
                  isLocallyOwned: descriptor.isLocallyOwned, productID: nil, variantID: nil, materialModel: descriptor.materialModel,
                  rendererCapability: descriptor.rendererCapability, personalized: descriptor.personalized),
            .init(type: descriptor.type, role: descriptor.role, schemaVersion: descriptor.schemaVersion, assetID: descriptor.assetID,
                  revision: descriptor.revision, coordinateSystem: descriptor.coordinateSystem, unit: descriptor.unit, origin: descriptor.origin,
                  scale: descriptor.scale, source: descriptor.source, provenance: descriptor.provenance, license: descriptor.license,
                  isLocallyOwned: descriptor.isLocallyOwned, productID: nil, variantID: nil, materialModel: .unsupported,
                  rendererCapability: descriptor.rendererCapability, personalized: descriptor.personalized)
        ]
        for fixture in invalid {
            XCTAssertEqual(resolve(everyday, variantID: "everyday-navy-small", association: .init(fixture: fixture)), .unavailable(.incompatibleFixture))
        }
    }
}
#endif
