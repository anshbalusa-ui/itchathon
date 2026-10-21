#if DEBUG
import Foundation
import XCTest
@testable import FitCheck

final class CatalogModelTests: XCTestCase {
    private func product(retailer: String = "shop", product: String = "tee", variantID: String = "v1") -> CatalogProduct {
        CatalogProduct(
            id: CatalogProductID(retailerID: retailer, productID: product), title: "Tee", description: nil,
            category: .tshirt, colors: [CatalogColor(id: "navy", name: "Navy", hex: "#112233")],
            sizes: [CatalogSize(id: "m", label: "M")],
            variants: [CatalogVariant(id: variantID, colorID: "navy", sizeID: "m", availability: .available, price: nil, finishedMeasurements: nil)],
            images: [], price: nil,
            provenance: CatalogProvenance(source: .synthetic, revision: "sample-v1", reference: "local-synthetic-fixture")
        )
    }

    private func document(_ products: [CatalogProduct]) throws -> Data {
        struct IncomingFeed: Encodable {
            let schemaVersion = 1
            let products: [CatalogProduct]
        }
        return try JSONEncoder().encode(IncomingFeed(products: products))
    }

    func testDecodeKeepsScopedIdentityAndStableSnapshot() throws {
        let data = try document([product()])
        let first = try CatalogDocument.decode(data)
        let second = try CatalogDocument.decode(data)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.products[0].id, CatalogProductID(retailerID: "shop", productID: "tee"))
        XCTAssertEqual(first.products[0].variants[0].id, "v1")
        XCTAssertEqual(try JSONDecoder().decode(CatalogProductID.self, from: JSONEncoder().encode(first.products[0].id)), first.products[0].id)
    }

    func testDuplicateProductAndRetailerScopedVariantIDs() throws {
        XCTAssertThrowsError(try CatalogDocument.decode(document([product(), product()])))
        XCTAssertThrowsError(try CatalogDocument.decode(document([product(), product(product: "other")])))
        let differentRetailers = try CatalogDocument.decode(document([product(), product(retailer: "other-shop")]))
        XCTAssertEqual(Set(differentRetailers.products.map(\.id.retailerID)), ["shop", "other-shop"])
    }

    func testDuplicateOptionsCombinationsAndOrphanReferencesAreRejected() throws {
        var p = product()
        let duplicateColor = CatalogColor(id: "navy", name: "Other", hex: nil)
        p = CatalogProduct(id: p.id, title: p.title, description: nil, category: p.category,
            colors: p.colors + [duplicateColor], sizes: p.sizes, variants: p.variants, images: [], price: nil, provenance: p.provenance)
        XCTAssertThrowsError(try CatalogDocument(schemaVersion: 1, products: [p]))
        let duplicateSize = CatalogSize(id: "m", label: "Medium")
        let repeatedSizeProduct = CatalogProduct(id: CatalogProductID(retailerID: "shop", productID: "size-test"), title: "Tee", description: nil, category: .tshirt,
            colors: [CatalogColor(id: "navy", name: "Navy", hex: nil)], sizes: [CatalogSize(id: "m", label: "M"), duplicateSize],
            variants: [], images: [], price: nil, provenance: CatalogProvenance(source: .unknown, revision: nil, reference: nil))
        XCTAssertThrowsError(try CatalogDocument(schemaVersion: 1, products: [repeatedSizeProduct]))

        let base = product()
        let duplicateCombination = CatalogVariant(id: "v2", colorID: "navy", sizeID: "m", availability: .unknown, price: nil, finishedMeasurements: nil)
        let duplicateOptions = CatalogProduct(id: base.id, title: base.title, description: nil, category: base.category,
            colors: base.colors, sizes: base.sizes, variants: base.variants + [duplicateCombination], images: [], price: nil, provenance: base.provenance)
        XCTAssertThrowsError(try CatalogDocument(schemaVersion: 1, products: [duplicateOptions]))
        let orphan = CatalogVariant(id: "orphan", colorID: "missing", sizeID: "m", availability: .unknown, price: nil, finishedMeasurements: nil)
        let orphanProduct = CatalogProduct(id: base.id, title: base.title, description: nil, category: base.category,
            colors: base.colors, sizes: base.sizes, variants: [orphan], images: [], price: nil, provenance: base.provenance)
        XCTAssertThrowsError(try CatalogDocument(schemaVersion: 1, products: [orphanProduct]))
    }

    func testMissingMalformedAndUnknownFields() throws {
        let missingTitle = #"{"schemaVersion":1,"products":[{"id":{"retailerID":"shop","productID":"tee"},"category":"tshirt","colors":[],"sizes":[],"variants":[],"images":[],"provenance":{"source":"unknown"}}]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(CatalogDocument.self, from: missingTitle))
        XCTAssertThrowsError(try CatalogDocument.decode(missingTitle))
        XCTAssertThrowsError(try CatalogDocument.decode(Data(#"{"schemaVersion":1,"products":[{"id":{"retailerID":" ","productID":"p"},"title":"T","category":"tshirt","colors":[],"sizes":[],"variants":[],"images":[],"provenance":{"source":"unknown"}}]}"#.utf8)))
        let unknownAndOptional = #"{"schemaVersion":1,"futureHeader":{"new":true},"products":[{"id":{"retailerID":"shop","productID":"tee"},"title":"Tee","category":"tshirt","colors":[],"sizes":[],"variants":[],"images":[],"provenance":{"source":"unknown","futureProvenance":4},"futureProduct":true}]}"#.data(using: .utf8)!
        let decoded = try CatalogDocument.decode(unknownAndOptional).products[0]
        XCTAssertEqual(decoded.id, CatalogProductID(retailerID: "shop", productID: "tee"))
        XCTAssertNil(decoded.description)
        XCTAssertNil(decoded.price)
        XCTAssertTrue(decoded.variants.isEmpty)
        XCTAssertThrowsError(try CatalogDocument.decode(Data(#"{"schemaVersion":2,"products":"changed shape"}"#.utf8))) { error in
            XCTAssertEqual(error as? CatalogValidationError, .unsupportedSchema(2))
        }
    }

    func testMeasurementsRequireFinishedGarmentKnownUnitsAndProvenance() throws {
        let provenance = CatalogProvenance(source: .synthetic, revision: "r1", reference: "fixture")
        let valid = CatalogFinishedMeasurements(basis: .finishedGarment, unit: .centimeters, values: [.chestFlatWidth: 52], provenance: provenance)
        try valid.validate()
        XCTAssertThrowsError(try CatalogFinishedMeasurements(basis: .bodyRecommendation, unit: .centimeters, values: [.chestFlatWidth: 52], provenance: provenance).validate())
        XCTAssertThrowsError(try CatalogFinishedMeasurements(basis: .finishedGarment, unit: .centimeters, values: [:], provenance: provenance).validate())
        for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try CatalogFinishedMeasurements(basis: .finishedGarment, unit: .inches, values: [.bodyLength: invalid], provenance: provenance).validate())
        }
        XCTAssertThrowsError(try CatalogFinishedMeasurements(basis: .finishedGarment, unit: .meters, values: [.bodyLength: 1], provenance: CatalogProvenance(source: .retailerProvided, revision: nil, reference: nil)).validate())
        let unknownSource = CatalogFinishedMeasurements(
            basis: .finishedGarment, unit: .centimeters, values: [.chestFlatWidth: 52],
            provenance: CatalogProvenance(source: .unknown, revision: nil, reference: nil)
        )
        XCTAssertThrowsError(try unknownSource.validate())
        let encoded = try JSONEncoder().encode(valid)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let values = try XCTUnwrap(json["values"] as? [String: Double])
        XCTAssertEqual(values["chestFlatWidth"], 52)
        XCTAssertEqual(try JSONDecoder().decode(CatalogFinishedMeasurements.self, from: encoded), valid)
        XCTAssertNil(product().variants[0].finishedMeasurements)
    }

    func testMoneyValidationAndExactCurrencyPresentation() throws {
        for (units, code, expected) in [(1234, "USD", "12.34"), (123, "JPY", "123"), (1234, "KWD", "1.234"), (0, "USD", "0.00")] {
            let money = CatalogMoney(minorUnits: Int64(units), currencyCode: code)
            try money.validate()
            let text = try XCTUnwrap(money.formatted(locale: Locale(identifier: "en_US_POSIX")))
            XCTAssertEqual(text.filter { "0123456789.".contains($0) }, expected)
            XCTAssertTrue(text.hasSuffix(code))
        }
        let large = CatalogMoney(minorUnits: Int64.max, currencyCode: "USD")
        let largeText = try XCTUnwrap(large.formatted(locale: Locale(identifier: "en_US_POSIX")))
        XCTAssertTrue(largeText.hasSuffix(".07 USD"))
        XCTAssertNil(CatalogMoney(minorUnits: -1, currencyCode: "USD").formatted())
        XCTAssertNil(CatalogMoney(minorUnits: 1, currencyCode: "XXX").formatted())
        XCTAssertNil(CatalogMoney(minorUnits: 1, currencyCode: "usd").formatted())
        XCTAssertNil(CatalogMoney(minorUnits: 1, currencyCode: "ZZZ").formatted())
        XCTAssertThrowsError(try CatalogMoney(minorUnits: -1, currencyCode: "USD").validate())
    }
}
#endif
