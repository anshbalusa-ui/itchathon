import Foundation

/// One real garment size and its actual garment measurements.
/// Do not infer these by simply scaling another size; brand grading varies.
struct GarmentSizeVariant: Codable, Equatable, Identifiable {
    var id: String { label }

    var label: String
    var chestFlat: Double
    var waistFlat: Double
    var shoulderWidth: Double
    var length: Double

    func asGarment(named name: String, category: GarmentCategory) -> GarmentProfile {
        GarmentProfile(
            name: "\(name) — \(label)",
            category: category,
            chestFlat: chestFlat,
            waistFlat: waistFlat,
            shoulderWidth: shoulderWidth,
            length: length
        )
    }
}

struct GarmentSizeChart: Codable, Equatable {
    var garmentName: String
    var brand: String?
    var category: GarmentCategory
    var sizes: [GarmentSizeVariant]

    static let demo = GarmentSizeChart(
        garmentName: "Everyday Tee",
        brand: "Demo Brand",
        category: .tshirt,
        sizes: [
            GarmentSizeVariant(label: "L", chestFlat: 0.54, waistFlat: 0.52, shoulderWidth: 0.46, length: 0.70),
            GarmentSizeVariant(label: "XL", chestFlat: 0.57, waistFlat: 0.55, shoulderWidth: 0.48, length: 0.72),
            GarmentSizeVariant(label: "2XL", chestFlat: 0.60, waistFlat: 0.58, shoulderWidth: 0.50, length: 0.74),
            GarmentSizeVariant(label: "3XL", chestFlat: 0.64, waistFlat: 0.62, shoulderWidth: 0.52, length: 0.76)
        ]
    )
}
