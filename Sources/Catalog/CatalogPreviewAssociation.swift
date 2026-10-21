#if DEBUG
import Foundation

struct CatalogIllustrativePreview: Hashable, Identifiable {
    let productID: CatalogProductID
    let variantID: String
    let colorID: String
    let sizeID: String
    let productTitle: String
    let colorName: String
    let sizeLabel: String
    fileprivate let material: RendererMaterial

    var id: Self { self }

    var rendererPresentation: RendererPresentation {
        RendererPresentation(
            navigationTitle: "Illustrative 3D Preview",
            context: "\(productTitle) · \(colorName) · \(sizeLabel)",
            initialMaterial: material,
            allowsMaterialChanges: false
        )
    }
}

enum CatalogPreviewUnavailable: Equatable {
    case selectVariant
    case unsupportedProduct
    case unsupportedColor
    case variantUnavailable
    case unverifiedSource
    case incompatibleFixture
    case invalidSelection

    var message: String {
        switch self {
        case .selectVariant: "Select an available size to preview this illustrative item."
        case .unsupportedProduct: "This product does not have an approved illustrative preview."
        case .unsupportedColor: "This color does not have an approved illustrative preview."
        case .variantUnavailable: "This variant is not available for preview."
        case .unverifiedSource: "This catalog entry is not the approved local synthetic sample."
        case .incompatibleFixture: "The illustrative preview fixture is unavailable or incompatible."
        case .invalidSelection: "Choose a valid color and size option to preview."
        }
    }
}

enum CatalogPreviewEligibility: Equatable {
    case eligible(CatalogIllustrativePreview)
    case unavailable(CatalogPreviewUnavailable)
}

struct CatalogPreviewAssociation {
    private struct ApprovedVariant {
        let productID: CatalogProductID
        let variantID: String
        let colorID: String
        let sizeID: String
        let material: RendererMaterial
    }

    private static let approved: [ApprovedVariant] = [
        .init(productID: .init(retailerID: "sample-studio", productID: "everyday-tee"), variantID: "everyday-navy-small", colorID: "navy", sizeID: "small", material: .navy),
        .init(productID: .init(retailerID: "sample-studio", productID: "everyday-tee"), variantID: "everyday-navy-medium", colorID: "navy", sizeID: "medium", material: .navy),
        .init(productID: .init(retailerID: "sample-studio", productID: "weekend-tee"), variantID: "weekend-sage-small", colorID: "sage", sizeID: "small", material: .sage),
        .init(productID: .init(retailerID: "sample-studio", productID: "weekend-tee"), variantID: "weekend-sage-medium", colorID: "sage", sizeID: "medium", material: .sage)
    ]

    private let fixture: RendererAssetDescriptor?

    init(fixture: RendererAssetDescriptor? = .garmentFixture) {
        self.fixture = fixture
    }

    func resolve(product: CatalogProduct, selectedVariant: CatalogVariant?, selectedColorID: String?, selectedSizeID: String?) -> CatalogPreviewEligibility {
        guard let fixture else { return .unavailable(.incompatibleFixture) }
        do { try fixture.validate(for: .garment) }
        catch { return .unavailable(.incompatibleFixture) }

        guard (try? product.validate()) != nil else { return .unavailable(.invalidSelection) }
        guard product.provenance.source == .synthetic,
              product.provenance.revision == "sample-v1",
              product.provenance.reference == "local-synthetic-fixture" else {
            return .unavailable(.unverifiedSource)
        }
        guard product.category == .tshirt,
              Self.approved.contains(where: { $0.productID == product.id }) else {
            return .unavailable(.unsupportedProduct)
        }
        guard let colorID = selectedColorID else { return .unavailable(.selectVariant) }
        guard let color = product.colors.first(where: { $0.id == colorID }),
              Self.approved.contains(where: { $0.productID == product.id && $0.colorID == colorID }),
              color.name == (colorID == "navy" ? "Navy" : "Sage"),
              color.hex == (colorID == "navy" ? "#24364B" : "#899786") else {
            return .unavailable(.unsupportedColor)
        }
        guard let sizeID = selectedSizeID else { return .unavailable(.selectVariant) }
        guard let size = product.sizes.first(where: { $0.id == sizeID }) else {
            return .unavailable(.invalidSelection)
        }
        guard let current = product.variants.first(where: { $0.colorID == colorID && $0.sizeID == sizeID }),
              current.availability == .available,
              let approved = Self.approved.first(where: {
                  $0.productID == product.id && $0.variantID == current.id &&
                  $0.colorID == colorID && $0.sizeID == sizeID
              }) else {
            return .unavailable(.variantUnavailable)
        }
        guard let selectedVariant else { return .unavailable(.selectVariant) }
        guard selectedVariant.id == current.id,
              selectedVariant.colorID == colorID, selectedVariant.sizeID == sizeID,
              selectedVariant.availability == .available else {
            return .unavailable(.invalidSelection)
        }

        let presentation = CatalogIllustrativePreview(
            productID: product.id, variantID: current.id, colorID: colorID, sizeID: sizeID,
            productTitle: product.title, colorName: color.name,
            sizeLabel: size.label, material: approved.material
        )
        return .eligible(presentation)
    }
}
#endif
