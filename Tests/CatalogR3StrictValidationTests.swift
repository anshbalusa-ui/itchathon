#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

final class CatalogR3StrictValidationTests: XCTestCase {
    private var products: [CatalogProduct] {
        get throws { try CatalogDocument.decode(SyntheticCatalog.data).products }
    }

    private func product(_ id: String, from products: [CatalogProduct]) -> CatalogProduct {
        products.first { $0.id.productID == id }!
    }

    private func resolve(_ product: CatalogProduct, sku: String) -> CatalogPreviewEligibility {
        let variant = product.variants.first { $0.id == sku }
        return CatalogPreviewAssociation().resolve(product: product, selectedVariant: variant,
                                                   selectedColorID: variant?.colorID, selectedSizeID: variant?.sizeID)
    }

    func testAllSixApprovedSKUsMapToReviewedMaterialAndGeometry() throws {
        let source = try products
        let cases: [(String, String, String, RendererMaterial, Bool)] = [
            ("everyday-tee", "everyday-navy-small", "small", .navy, false),
            ("everyday-tee", "everyday-navy-medium", "medium", .navy, false),
            ("weekend-tee", "weekend-sage-small", "small", .sage, false),
            ("weekend-tee", "weekend-sage-medium", "medium", .sage, false),
            ("geometric-vest", "geometric-vest-navy-small", "small", .navy, true),
            ("geometric-vest", "geometric-vest-navy-medium", "medium", .navy, true)
        ]
        for (productID, sku, size, material, bundled) in cases {
            let item = product(productID, from: source)
            guard case let .eligible(preview) = resolve(item, sku: sku) else {
                return XCTFail("Expected approved SKU \(sku)")
            }
            XCTAssertEqual(preview.productID, item.id)
            XCTAssertEqual(preview.variantID, sku)
            XCTAssertEqual(preview.sizeID, size)
            XCTAssertEqual(preview.rendererPresentation.initialMaterial, material)
            XCTAssertEqual(preview.rendererPresentation.geometrySource, bundled ? .bundled(.reviewedVest) : .procedural)
            XCTAssertFalse(preview.rendererPresentation.allowsMaterialChanges)
        }
    }

    func testApprovedVestHasNoCommercialOfferPhotographyOrFinishedMeasurements() throws {
        let vest = product("geometric-vest", from: try products)
        XCTAssertNil(vest.price)
        XCTAssertTrue(vest.images.isEmpty)
        XCTAssertTrue(vest.variants.allSatisfy { $0.price == nil && $0.finishedMeasurements == nil })
    }
    func testVestRequiresExactBundledDescriptorAndDoesNotBorrowProceduralFixture() throws {
        let vest = product("geometric-vest", from: try products)
        let fixtures: [RendererBundledAssetDescriptor?] = [nil, .incompatibleDemo]
        for descriptor in fixtures {
            let association = CatalogPreviewAssociation(bundledFixture: descriptor)
            XCTAssertEqual(association.resolve(
                product: vest, selectedVariant: vest.variants[0],
                selectedColorID: "navy", selectedSizeID: "small"
            ), .unavailable(.incompatibleFixture))
        }
        let missingProcedural = CatalogPreviewAssociation(fixture: nil)
        let tee = product("everyday-tee", from: try products)
        XCTAssertEqual(missingProcedural.resolve(
            product: tee, selectedVariant: tee.variants[0],
            selectedColorID: "navy", selectedSizeID: "small"
        ), .unavailable(.incompatibleFixture))
        guard case .eligible(let vestPreview) = missingProcedural.resolve(
            product: vest, selectedVariant: vest.variants[0], selectedColorID: "navy", selectedSizeID: "small"
        ) else { return XCTFail("Reviewed file-backed authorization must not depend on the procedural fixture") }
        XCTAssertEqual(vestPreview.rendererPresentation.geometrySource, .bundled(.reviewedVest))
        guard case .eligible(let teePreview) = CatalogPreviewAssociation(bundledFixture: nil).resolve(
            product: tee, selectedVariant: tee.variants[0], selectedColorID: "navy", selectedSizeID: "small"
        ) else { return XCTFail("Procedural authorization must not depend on the bundled fixture") }
        XCTAssertEqual(teePreview.rendererPresentation.geometrySource, .procedural)
    }

    func testVestMustUseListedAvailableOptionsAndExactIdentity() throws {
        let vest = product("geometric-vest", from: try products)
        let association = CatalogPreviewAssociation()
        XCTAssertEqual(association.resolve(product: vest, selectedVariant: nil, selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.selectVariant))
        XCTAssertEqual(association.resolve(product: vest, selectedVariant: vest.variants[0], selectedColorID: nil, selectedSizeID: "small"),
                       .unavailable(.selectVariant))
        XCTAssertEqual(association.resolve(product: vest, selectedVariant: vest.variants[0], selectedColorID: "navy", selectedSizeID: nil),
                       .unavailable(.selectVariant))
        XCTAssertEqual(association.resolve(product: vest, selectedVariant: vest.variants[0], selectedColorID: "navy", selectedSizeID: "medium"),
                       .unavailable(.invalidSelection))

        for availability: CatalogAvailability in [.outOfStock, .unknown, .discontinued] {
            let first = vest.variants[0]
            let unavailable = CatalogVariant(id: first.id, colorID: first.colorID, sizeID: first.sizeID, availability: availability, price: nil, finishedMeasurements: nil)
            let changed = CatalogProduct(id: vest.id, title: vest.title, description: vest.description, category: vest.category,
                                         colors: vest.colors, sizes: vest.sizes, variants: [unavailable, vest.variants[1]],
                                         images: vest.images, price: vest.price, provenance: vest.provenance)
            XCTAssertEqual(association.resolve(product: changed, selectedVariant: unavailable, selectedColorID: "navy", selectedSizeID: "small"),
                           .unavailable(.variantUnavailable))
        }
    }

    func testVestRequiresExactSyntheticProvenanceCategoryAndNavyMetadata() throws {
        let vest = product("geometric-vest", from: try products)
        let original = vest.variants[0]
        let association = CatalogPreviewAssociation()
        for provenance in [
            CatalogProvenance(source: .retailerProvided, revision: "sample-v1", reference: "local-synthetic-fixture"),
            CatalogProvenance(source: .synthetic, revision: "wrong", reference: "local-synthetic-fixture"),
            CatalogProvenance(source: .synthetic, revision: "sample-v1", reference: "wrong")
        ] {
            let changed = CatalogProduct(id: vest.id, title: vest.title, description: vest.description, category: vest.category,
                                         colors: vest.colors, sizes: vest.sizes, variants: vest.variants, images: vest.images,
                                         price: vest.price, provenance: provenance)
            XCTAssertEqual(association.resolve(product: changed, selectedVariant: original, selectedColorID: "navy", selectedSizeID: "small"),
                           .unavailable(.unverifiedSource))
        }
        let wrongCategory = CatalogProduct(id: vest.id, title: vest.title, description: vest.description, category: .tshirt,
                                           colors: vest.colors, sizes: vest.sizes, variants: vest.variants, images: vest.images,
                                           price: vest.price, provenance: vest.provenance)
        XCTAssertEqual(association.resolve(product: wrongCategory, selectedVariant: original, selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.unsupportedProduct))
        let wrongRetailer = CatalogProduct(id: .init(retailerID: "foreign", productID: vest.id.productID), title: vest.title,
                                           description: vest.description, category: vest.category, colors: vest.colors, sizes: vest.sizes,
                                           variants: vest.variants, images: vest.images, price: vest.price, provenance: vest.provenance)
        XCTAssertEqual(association.resolve(product: wrongRetailer, selectedVariant: original, selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.unsupportedProduct))
        let wrongColor = CatalogColor(id: "navy", name: "Navy", hex: "#FFFFFF")
        let recolored = CatalogProduct(id: vest.id, title: vest.title, description: vest.description, category: vest.category,
                                       colors: [wrongColor], sizes: vest.sizes, variants: vest.variants, images: vest.images,
                                       price: vest.price, provenance: vest.provenance)
        XCTAssertEqual(association.resolve(product: recolored, selectedVariant: original, selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.unsupportedColor))
    }

    func testVestRejectsMutatedBundledDescriptorRevisionCapabilityAndLicense() throws {
        let vest = product("geometric-vest", from: try products)
        let reviewed = RendererBundledAssetDescriptor.reviewedVest
        let asset = reviewed.asset
        let variants: [RendererBundledAssetDescriptor] = [
            .init(asset: RendererAssetDescriptor(type: asset.type, role: asset.role, schemaVersion: asset.schemaVersion,
                                                 assetID: asset.assetID, revision: asset.revision + 1, coordinateSystem: asset.coordinateSystem,
                                                 unit: asset.unit, origin: asset.origin, scale: asset.scale, source: asset.source,
                                                 provenance: asset.provenance, license: asset.license, isLocallyOwned: asset.isLocallyOwned,
                                                 productID: asset.productID, variantID: asset.variantID, materialModel: asset.materialModel,
                                                 rendererCapability: asset.rendererCapability, personalized: asset.personalized),
                 resourceName: reviewed.resourceName, resourceExtension: reviewed.resourceExtension, sha256: reviewed.sha256),
            .init(asset: RendererAssetDescriptor(type: asset.type, role: asset.role, schemaVersion: asset.schemaVersion,
                                                 assetID: asset.assetID, revision: asset.revision, coordinateSystem: asset.coordinateSystem,
                                                 unit: asset.unit, origin: asset.origin, scale: asset.scale, source: asset.source,
                                                 provenance: asset.provenance, license: .commercial, isLocallyOwned: asset.isLocallyOwned,
                                                 productID: asset.productID, variantID: asset.variantID, materialModel: asset.materialModel,
                                                 rendererCapability: asset.rendererCapability, personalized: asset.personalized),
                 resourceName: reviewed.resourceName, resourceExtension: reviewed.resourceExtension, sha256: reviewed.sha256),
            .init(asset: RendererAssetDescriptor(type: asset.type, role: asset.role, schemaVersion: asset.schemaVersion,
                                                 assetID: asset.assetID, revision: asset.revision, coordinateSystem: asset.coordinateSystem,
                                                 unit: asset.unit, origin: asset.origin, scale: asset.scale, source: asset.source,
                                                 provenance: asset.provenance, license: asset.license, isLocallyOwned: asset.isLocallyOwned,
                                                 productID: asset.productID, variantID: asset.variantID, materialModel: asset.materialModel,
                                                 rendererCapability: "unsupported", personalized: asset.personalized),
                 resourceName: reviewed.resourceName, resourceExtension: reviewed.resourceExtension, sha256: reviewed.sha256),
            .init(asset: RendererAssetDescriptor(type: asset.type, role: asset.role, schemaVersion: asset.schemaVersion,
                                                 assetID: "unapproved-asset", revision: asset.revision, coordinateSystem: asset.coordinateSystem,
                                                 unit: asset.unit, origin: asset.origin, scale: asset.scale, source: asset.source,
                                                 provenance: asset.provenance, license: asset.license, isLocallyOwned: asset.isLocallyOwned,
                                                 productID: asset.productID, variantID: asset.variantID, materialModel: asset.materialModel,
                                                 rendererCapability: asset.rendererCapability, personalized: asset.personalized),
                 resourceName: reviewed.resourceName, resourceExtension: reviewed.resourceExtension, sha256: reviewed.sha256),
            .init(asset: asset, resourceName: "../FitCheckGeometricVest", resourceExtension: reviewed.resourceExtension, sha256: reviewed.sha256),
            .init(asset: asset, resourceName: reviewed.resourceName, resourceExtension: "obj", sha256: reviewed.sha256)
        ]
        for descriptor in variants {
            let association = CatalogPreviewAssociation(bundledFixture: descriptor)
            XCTAssertEqual(association.resolve(product: vest, selectedVariant: vest.variants[0],
                                               selectedColorID: "navy", selectedSizeID: "small"),
                           .unavailable(.incompatibleFixture))
        }
    }

    func testMatchingTitlesAndOptionLabelsCannotAuthorizeAnotherProductOrSKU() throws {
        let vest = product("geometric-vest", from: try products)
        let selected = vest.variants[0]
        let association = CatalogPreviewAssociation()
        let unrelated = CatalogProduct(
            id: .init(retailerID: vest.id.retailerID, productID: "unapproved-vest"),
            title: vest.title, description: vest.description, category: vest.category,
            colors: vest.colors, sizes: vest.sizes, variants: vest.variants,
            images: [], price: nil, provenance: vest.provenance
        )
        XCTAssertEqual(association.resolve(product: unrelated, selectedVariant: selected,
                                           selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.unsupportedProduct))
        for response in [
            CatalogVariant(id: "borrowed-sku", colorID: "navy", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "sage", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "navy", sizeID: "medium", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: selected.id, colorID: "navy", sizeID: "small", availability: .unknown, price: nil, finishedMeasurements: nil)
        ] {
            XCTAssertEqual(association.resolve(product: vest, selectedVariant: response,
                                               selectedColorID: "navy", selectedSizeID: "small"),
                           .unavailable(.invalidSelection))
        }
        let foreign = CatalogVariant(id: "borrowed-sku", colorID: "navy", sizeID: "small",
                                     availability: .available, price: nil, finishedMeasurements: nil)
        let unapprovedListing = CatalogProduct(
            id: vest.id, title: vest.title, description: vest.description, category: vest.category,
            colors: vest.colors, sizes: vest.sizes, variants: [foreign, vest.variants[1]],
            images: [], price: nil, provenance: vest.provenance
        )
        XCTAssertEqual(association.resolve(product: unapprovedListing, selectedVariant: foreign,
                                           selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.variantUnavailable))
        let swapped = [
            CatalogVariant(id: "geometric-vest-navy-medium", colorID: "navy", sizeID: "small", availability: .available, price: nil, finishedMeasurements: nil),
            CatalogVariant(id: "geometric-vest-navy-small", colorID: "navy", sizeID: "medium", availability: .available, price: nil, finishedMeasurements: nil)
        ]
        let wrongMembership = CatalogProduct(
            id: vest.id, title: vest.title, description: vest.description, category: vest.category,
            colors: vest.colors, sizes: vest.sizes, variants: swapped,
            images: [], price: nil, provenance: vest.provenance
        )
        XCTAssertEqual(association.resolve(product: wrongMembership, selectedVariant: swapped[0],
                                           selectedColorID: "navy", selectedSizeID: "small"),
                       .unavailable(.variantUnavailable))
    }

}
#endif
