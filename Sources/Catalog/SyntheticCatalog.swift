#if DEBUG
import Foundation

/// Fictional browsing fixtures, not an actual retailer, stock feed, or price offer.
/// No garment measurements or product photos have been supplied or invented.
enum SyntheticCatalog {
    static let data = Data(#"""
    {
      "schemaVersion": 1,
      "products": [
        {
          "id": { "retailerID": "sample-studio", "productID": "everyday-tee" },
          "title": "Everyday Tee",
          "description": "An everyday T-shirt concept for exploring colors and sizes. This is an illustrative product, not an item offered for sale.",
          "category": "tshirt",
          "colors": [
            { "id": "navy", "name": "Navy", "hex": "#24364B" },
            { "id": "cream", "name": "Cream", "hex": "#E8E0CC" }
          ],
          "sizes": [
            { "id": "small", "label": "S" },
            { "id": "medium", "label": "M" },
            { "id": "large", "label": "L" }
          ],
          "variants": [
            { "id": "everyday-navy-small", "colorID": "navy", "sizeID": "small", "availability": "available", "price": { "minorUnits": 1800, "currencyCode": "USD" } },
            { "id": "everyday-navy-medium", "colorID": "navy", "sizeID": "medium", "availability": "available", "price": { "minorUnits": 1800, "currencyCode": "USD" } },
            { "id": "everyday-navy-large", "colorID": "navy", "sizeID": "large", "availability": "outOfStock", "price": { "minorUnits": 1800, "currencyCode": "USD" } },
            { "id": "everyday-cream-small", "colorID": "cream", "sizeID": "small", "availability": "outOfStock", "price": { "minorUnits": 2000, "currencyCode": "USD" } },
            { "id": "everyday-cream-medium", "colorID": "cream", "sizeID": "medium", "availability": "available", "price": { "minorUnits": 2000, "currencyCode": "USD" } },
            { "id": "everyday-cream-large", "colorID": "cream", "sizeID": "large", "availability": "unknown" }
          ],
          "images": [],
          "price": { "minorUnits": 1800, "currencyCode": "USD" },
          "provenance": { "source": "synthetic", "revision": "sample-v1", "reference": "local-synthetic-fixture" }
        },
        {
          "id": { "retailerID": "sample-studio", "productID": "weekend-tee" },
          "title": "Weekend Tee",
          "category": "tshirt",
          "colors": [ { "id": "sage", "name": "Sage", "hex": "#899786" } ],
          "sizes": [ { "id": "small", "label": "S" }, { "id": "medium", "label": "M" } ],
          "variants": [
            { "id": "weekend-sage-small", "colorID": "sage", "sizeID": "small", "availability": "available" },
            { "id": "weekend-sage-medium", "colorID": "sage", "sizeID": "medium", "availability": "available" }
          ],
          "images": [],
          "provenance": { "source": "synthetic", "revision": "sample-v1", "reference": "local-synthetic-fixture" }
        },
        {
          "id": { "retailerID": "sample-studio", "productID": "archived-tee" },
          "title": "Archive Tee",
          "description": "An unavailable sample item demonstrating how an archived product remains understandable without a purchase action.",
          "category": "tshirt",
          "colors": [ { "id": "graphite", "name": "Graphite", "hex": "#57595C" } ],
          "sizes": [ { "id": "medium", "label": "M" } ],
          "variants": [ { "id": "archive-graphite-medium", "colorID": "graphite", "sizeID": "medium", "availability": "discontinued" } ],
          "images": [],
          "provenance": { "source": "synthetic", "revision": "sample-v1", "reference": "local-synthetic-fixture" }
        }
      ]
    }
    """#.utf8)
}
#endif
