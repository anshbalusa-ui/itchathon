#if DEBUG
import Foundation

struct CatalogProductID: Hashable, Codable, Sendable {
    let retailerID: String
    let productID: String

    func validate() throws {
        try CatalogValidation.requireIdentifier(retailerID, field: "retailerID")
        try CatalogValidation.requireIdentifier(productID, field: "productID")
    }
}

enum CatalogSource: String, Codable, Sendable { case synthetic, retailerProvided, unknown }

enum CatalogCategory: String, Codable, Sendable { case tshirt, unknown }
enum CatalogAvailability: String, Codable, Sendable { case available, outOfStock, unknown, discontinued }
enum CatalogMediaKind: String, Codable, Sendable { case bundledAsset, remoteURL }
enum CatalogMediaSource: String, Codable, Sendable { case synthetic, retailerAuthorized, licensed, unknown }
enum CatalogMeasurementBasis: String, Codable, Sendable { case finishedGarment, bodyRecommendation }
enum CatalogLengthUnit: String, Codable, Sendable { case centimeters, inches, meters }
enum CatalogGarmentDimension: String, Codable, Sendable { case chestFlatWidth, shoulderWidth, bodyLength, sleeveLength }

struct CatalogProvenance: Codable, Equatable, Sendable {
    let source: CatalogSource
    let revision: String?
    let reference: String?

    func validate(measurement: Bool = false) throws {
        if let revision { try CatalogValidation.requireText(revision, field: "provenance.revision") }
        if let reference { try CatalogValidation.requireText(reference, field: "provenance.reference") }
        if measurement, source != .unknown, (revision == nil || reference == nil) {
            throw CatalogValidationError.invalidField("provenance")
        }
    }
}

struct CatalogColor: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let hex: String?

    func validate() throws {
        try CatalogValidation.requireIdentifier(id, field: "color.id")
        try CatalogValidation.requireText(name, field: "color.name")
        if let hex, hex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
            throw CatalogValidationError.invalidField("color.hex")
        }
    }
}

struct CatalogSize: Codable, Equatable, Sendable {
    let id: String
    let label: String

    func validate() throws {
        try CatalogValidation.requireIdentifier(id, field: "size.id")
        try CatalogValidation.requireText(label, field: "size.label")
    }
}

struct CatalogMedia: Codable, Equatable, Sendable {
    let kind: CatalogMediaKind
    let reference: String
    let source: CatalogMediaSource
    let rightsReference: String?
    let altText: String

    func validate() throws {
        try CatalogValidation.requireText(reference, field: "media.reference")
        try CatalogValidation.requireText(altText, field: "media.altText")
        if let rightsReference { try CatalogValidation.requireText(rightsReference, field: "media.rightsReference") }
        if source != .unknown, rightsReference == nil { throw CatalogValidationError.invalidField("media.rightsReference") }
        switch kind {
        case .bundledAsset:
            if reference.contains("/") || reference.contains("\\") { throw CatalogValidationError.invalidField("media.reference") }
        case .remoteURL:
            guard let url = URL(string: reference), url.scheme?.lowercased() == "https",
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw CatalogValidationError.invalidField("media.reference")
            }
        }
    }
}

struct CatalogMoney: Codable, Equatable, Sendable {
    private static let isoCurrencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
    let minorUnits: Int64
    let currencyCode: String

    func validate() throws {
        guard minorUnits >= 0, currencyCode == currencyCode.uppercased(),
              CatalogMoney.isoCurrencyCodes.contains(currencyCode),
              currencyCode != "XXX", currencyCode != "XTS" else {
            throw CatalogValidationError.invalidPrice
    }
    }

    /// Produces an exact decimal amount; the ISO code is appended so locale symbols cannot obscure the currency.
    func formatted(locale: Locale = .current) -> String? {
        guard (try? validate()) != nil else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        guard formatter.maximumFractionDigits >= 0, formatter.maximumFractionDigits <= 9 else { return nil }
        let digits = formatter.maximumFractionDigits
        var amount = Decimal(minorUnits)
        var divisor = Decimal(1)
        for _ in 0..<digits { divisor *= 10 }
        amount /= divisor
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        guard let result = formatter.string(from: NSDecimalNumber(decimal: amount)) else { return nil }
        return "\(result) \(currencyCode)"
    }
}

struct CatalogFinishedMeasurements: Codable, Equatable, Sendable {
    let basis: CatalogMeasurementBasis
    let unit: CatalogLengthUnit
    let values: [CatalogGarmentDimension: Double]
    let provenance: CatalogProvenance

    func validate() throws {
        guard basis == .finishedGarment, !values.isEmpty else { throw CatalogValidationError.invalidMeasurements }
        for value in values.values where !value.isFinite || value <= 0 {
            throw CatalogValidationError.invalidMeasurements
        }
        guard provenance.source != .unknown else { throw CatalogValidationError.invalidMeasurements }
        try provenance.validate(measurement: true)
    }
}

private struct CatalogDimensionCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension CatalogFinishedMeasurements {
    private enum CodingKeys: String, CodingKey { case basis, unit, values, provenance }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basis = try container.decode(CatalogMeasurementBasis.self, forKey: .basis)
        unit = try container.decode(CatalogLengthUnit.self, forKey: .unit)
        provenance = try container.decode(CatalogProvenance.self, forKey: .provenance)
        let dimensions = try container.nestedContainer(keyedBy: CatalogDimensionCodingKey.self, forKey: .values)
        var decodedValues: [CatalogGarmentDimension: Double] = [:]
        for key in dimensions.allKeys {
            guard let dimension = CatalogGarmentDimension(rawValue: key.stringValue) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: dimensions, debugDescription: "Unknown garment dimension")
            }
            decodedValues[dimension] = try dimensions.decode(Double.self, forKey: key)
        }
        values = decodedValues
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(basis, forKey: .basis)
        try container.encode(unit, forKey: .unit)
        try container.encode(provenance, forKey: .provenance)
        var dimensions = container.nestedContainer(keyedBy: CatalogDimensionCodingKey.self, forKey: .values)
        for (dimension, value) in values {
            try dimensions.encode(value, forKey: CatalogDimensionCodingKey(stringValue: dimension.rawValue)!)
        }
    }
}

struct CatalogVariant: Codable, Equatable, Sendable {
    let id: String
    let colorID: String
    let sizeID: String
    let availability: CatalogAvailability
    let price: CatalogMoney?
    let finishedMeasurements: CatalogFinishedMeasurements?

    func validate() throws {
        try CatalogValidation.requireIdentifier(id, field: "variant.id")
        try CatalogValidation.requireIdentifier(colorID, field: "variant.colorID")
        try CatalogValidation.requireIdentifier(sizeID, field: "variant.sizeID")
        try price?.validate()
        try finishedMeasurements?.validate()
    }
}

struct CatalogProduct: Codable, Equatable, Sendable {
    let id: CatalogProductID
    let title: String
    let description: String?
    let category: CatalogCategory
    let colors: [CatalogColor]
    let sizes: [CatalogSize]
    let variants: [CatalogVariant]
    let images: [CatalogMedia]
    let price: CatalogMoney?
    let provenance: CatalogProvenance

    func validate() throws {
        try id.validate()
        try CatalogValidation.requireText(title, field: "product.title")
        if let description { try CatalogValidation.requireText(description, field: "product.description") }
        try provenance.validate()
        try price?.validate()
        var colorIDs = Set<String>()
        for color in colors {
            try color.validate()
            guard colorIDs.insert(color.id).inserted else { throw CatalogValidationError.duplicateIdentifier("color:\(color.id)") }
        }
        var sizeIDs = Set<String>()
        for size in sizes {
            try size.validate()
            guard sizeIDs.insert(size.id).inserted else { throw CatalogValidationError.duplicateIdentifier("size:\(size.id)") }
        }
        var combinations = Set<String>()
        var variantIDs = Set<String>()
        for variant in variants {
            try variant.validate()
            guard colorIDs.contains(variant.colorID), sizeIDs.contains(variant.sizeID) else {
                throw CatalogValidationError.invalidField("variant.optionReference")
            }
            guard variantIDs.insert(variant.id).inserted else { throw CatalogValidationError.duplicateIdentifier("variant:\(variant.id)") }
            let combination = "\(variant.colorID)\u{0}\(variant.sizeID)"
            guard combinations.insert(combination).inserted else { throw CatalogValidationError.duplicateIdentifier("variant.combination") }
        }
        for image in images { try image.validate() }
    }
}

enum CatalogValidationError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidField(String)
    case duplicateIdentifier(String)
    case invalidMeasurements
    case invalidPrice
}

struct CatalogDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let products: [CatalogProduct]

    init(schemaVersion: Int = 1, products: [CatalogProduct]) throws {
        guard schemaVersion == 1 else { throw CatalogValidationError.unsupportedSchema(schemaVersion) }
        self.schemaVersion = schemaVersion
        self.products = products
        try validate()
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, products }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            products: container.decode([CatalogProduct].self, forKey: .products)
        )
    }

    /// Reads the version header before decoding products, so unsupported schemas report the version first.
    static func decode(_ data: Data) throws -> CatalogDocument {
        let header = try JSONDecoder().decode(CatalogVersionHeader.self, from: data)
        guard header.schemaVersion == 1 else { throw CatalogValidationError.unsupportedSchema(header.schemaVersion) }
        return try JSONDecoder().decode(CatalogDocument.self, from: data)
    }

    private struct CatalogVersionHeader: Decodable { let schemaVersion: Int }

    func validate() throws {
        guard schemaVersion == 1 else { throw CatalogValidationError.unsupportedSchema(schemaVersion) }
        var productIDs = Set<CatalogProductID>()
        var variantIDsByRetailer: [String: Set<String>] = [:]
        for product in products {
            try product.validate()
            guard productIDs.insert(product.id).inserted else {
                throw CatalogValidationError.duplicateIdentifier("product:\(product.id.retailerID)/\(product.id.productID)")
            }
            for variant in product.variants {
                guard variantIDsByRetailer[product.id.retailerID, default: []].insert(variant.id).inserted else {
                    throw CatalogValidationError.duplicateIdentifier("variant:\(product.id.retailerID)/\(variant.id)")
                }
            }
        }
    }
}

private enum CatalogValidation {
    static func requireText(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CatalogValidationError.invalidField(field)
        }
    }

    static func requireIdentifier(_ value: String, field: String) throws {
        try requireText(value, field: field)
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CatalogValidationError.invalidField(field)
        }
    }
}

#endif
