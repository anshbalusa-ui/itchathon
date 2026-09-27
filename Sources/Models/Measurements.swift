import Foundation

enum MeasurementKey: String, Codable, CaseIterable, Identifiable {
    case chestCircumference
    case waistCircumference
    case hipCircumference
    case shoulderWidth
    case torsoLength
    case garmentChestFlat
    case garmentWaistFlat
    case garmentShoulderWidth
    case garmentLength

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chestCircumference: return "Chest"
        case .waistCircumference: return "Waist"
        case .hipCircumference: return "Hip"
        case .shoulderWidth: return "Shoulders"
        case .torsoLength: return "Torso"
        case .garmentChestFlat: return "Garment chest"
        case .garmentWaistFlat: return "Garment waist"
        case .garmentShoulderWidth: return "Garment shoulders"
        case .garmentLength: return "Garment length"
        }
    }
}

struct Measurement: Codable, Equatable, Identifiable {
    var id = UUID()
    var key: MeasurementKey
    var meters: Double
    var confidence: Double?

    var centimeters: Double { meters * 100 }
}
