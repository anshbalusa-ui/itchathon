import Foundation

/// One real garment size and its actual garment measurements.
/// Do not infer these by simply scaling another size; brand grading varies.
struct GarmentSizeVariant: Codable, Equatable, Identifiable {
    var id: UUID = UUID()

    var label: String
    var chestFlat: Double
    var waistFlat: Double
    var shoulderWidth: Double
    var length: Double
    var origins: [String: MeasurementOrigin]? = nil
    var waistAtNavel: Bool? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case chestFlat
        case waistFlat
        case shoulderWidth
        case length
        case origins
        case waistAtNavel
    }

    init(
        id: UUID = UUID(),
        label: String,
        chestFlat: Double,
        waistFlat: Double,
        shoulderWidth: Double,
        length: Double,
        origins: [String: MeasurementOrigin]? = nil,
        waistAtNavel: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.chestFlat = chestFlat
        self.waistFlat = waistFlat
        self.shoulderWidth = shoulderWidth
        self.length = length
        self.origins = origins
        self.waistAtNavel = waistAtNavel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decode(String.self, forKey: .label)
        chestFlat = try container.decode(Double.self, forKey: .chestFlat)
        waistFlat = try container.decode(Double.self, forKey: .waistFlat)
        shoulderWidth = try container.decode(Double.self, forKey: .shoulderWidth)
        length = try container.decode(Double.self, forKey: .length)
        origins = try container.decodeIfPresent([String: MeasurementOrigin].self, forKey: .origins)
        waistAtNavel = try container.decodeIfPresent(Bool.self, forKey: .waistAtNavel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(chestFlat, forKey: .chestFlat)
        try container.encode(waistFlat, forKey: .waistFlat)
        try container.encode(shoulderWidth, forKey: .shoulderWidth)
        try container.encode(length, forKey: .length)
        try container.encodeIfPresent(origins, forKey: .origins)
        try container.encodeIfPresent(waistAtNavel, forKey: .waistAtNavel)
    }

    func asGarment(named name: String, category: GarmentCategory) -> GarmentProfile {
        GarmentProfile(
            name: "\(name) — \(label)",
            category: category,
            chestFlat: chestFlat,
            waistFlat: waistFlat,
            shoulderWidth: shoulderWidth,
            length: length,
            waistAtNavel: waistAtNavel,
            origins: origins
        )
    }
}

enum ChartMeasurementBasis: String, Codable {
    case finishedGarment
    case bodyRecommendation
}

enum ChestInputBasis: String, CaseIterable {
    case flatWidth
    case circumference

    func flatMeters(from enteredMeters: Double) -> Double {
        self == .flatWidth ? enteredMeters : enteredMeters / 2
    }
}

struct GarmentSizeChart: Codable, Equatable {
    var garmentName: String
    var brand: String?
    var category: GarmentCategory
    var sizes: [GarmentSizeVariant]
    var measurementBasis: ChartMeasurementBasis? = nil
    var sourceNote: String? = nil

    static let demo = GarmentSizeChart(
        garmentName: "Everyday Tee",
        brand: "Demo Brand",
        category: .tshirt,
        sizes: [
            GarmentSizeVariant(label: "L", chestFlat: 0.52, waistFlat: 0.50, shoulderWidth: 0.45, length: 0.70),
            GarmentSizeVariant(label: "XL", chestFlat: 0.55, waistFlat: 0.53, shoulderWidth: 0.47, length: 0.72),
            GarmentSizeVariant(label: "2XL", chestFlat: 0.58, waistFlat: 0.55, shoulderWidth: 0.49, length: 0.74),
            GarmentSizeVariant(label: "3XL", chestFlat: 0.62, waistFlat: 0.59, shoulderWidth: 0.51, length: 0.76)
        ],
        measurementBasis: .finishedGarment,
        sourceNote: "Synthetic test data"
    )
}
