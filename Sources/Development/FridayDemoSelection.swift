#if DEBUG
import Combine
import Foundation

/// A curated view of the existing catalog, never an alternate geometry authority.
struct FridayDemoProduct: Identifiable {
    let product: CatalogProduct
    let previews: [CatalogIllustrativePreview]
    let description: String
    var id: String { product.id.productID }
}

@MainActor
final class FridayDemoSelection: ObservableObject {
    @Published private(set) var products: [FridayDemoProduct] = []
    @Published private(set) var preview: CatalogIllustrativePreview?
    @Published private(set) var failure: String?
    private let data: Data

    init(data: Data = SyntheticCatalog.data) {
        self.data = data
        reload()
    }

    var selectedProduct: FridayDemoProduct? {
        products.first { $0.product.id == preview?.productID }
    }

    func reload() {
        preview = nil
        products = []
        failure = nil
        do {
            let document = try CatalogDocument.decode(data)
            let association = CatalogPreviewAssociation()
            var curated: [FridayDemoProduct] = []
            for id in ["everyday-tee", "weekend-tee", "geometric-vest"] {
                guard let product = document.products.first(where: {
                    $0.id == CatalogProductID(retailerID: "sample-studio", productID: id)
                }) else {
                    throw CatalogRepositoryError.invalidData
                }
                let description: String
                if let provided = product.description {
                    description = provided
                } else if id == "weekend-tee" {
                    // Authored showcase copy, not invented retailer product data.
                    // Keep the catalog's missing-information fixture unchanged.
                    description = "A fictional Sage shirt illustration using the same sample geometry as the Everyday Tee. Demo data only; not a physical garment or an offer for sale."
                } else {
                    throw CatalogRepositoryError.invalidData
                }
                let color = id == "weekend-tee" ? "sage" : "navy"
                var previews: [CatalogIllustrativePreview] = []
                for size in ["small", "medium"] {
                    let variant = product.variants.first { $0.colorID == color && $0.sizeID == size }
                    guard case .eligible(let approved) = association.resolve(
                        product: product, selectedVariant: variant,
                        selectedColorID: color, selectedSizeID: size
                    ) else { throw CatalogRepositoryError.invalidData }
                    previews.append(approved)
                }
                curated.append(FridayDemoProduct(product: product, previews: previews, description: description))
            }
            products = curated
            preview = curated.first?.previews.first
        } catch {
            failure = "The reviewed sample collection could not be loaded. Retry to reload the local demo data."
        }
    }

    func select(productID: String, sizeID: String) {
        guard let product = products.first(where: { $0.id == productID }),
              let approved = product.previews.first(where: { $0.sizeID == sizeID }) else {
            // Remove the old preview: an unsupported selection must not look successful.
            preview = nil
            failure = "This sample combination has no approved 3D preview. Choose a supported item or reload the collection."
            return
        }
        failure = nil
        preview = approved
    }
}
#endif
