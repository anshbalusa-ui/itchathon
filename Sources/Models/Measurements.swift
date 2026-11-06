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

enum MeasurementSource: String, Codable {
    case manual
    case external
    case bodyScan
    case garmentScan
    case retailer
}

struct MeasurementOrigin: Codable, Equatable {
    var source: MeasurementSource
    var wasEdited = false
    var verifiedWithTape = false
    var observedErrorMeters: Double? = nil

    var isValid: Bool {
        observedErrorMeters.map { $0.isFinite && $0 >= 0 } ?? true
    }
}

enum LengthUnit: String, CaseIterable, Identifiable {
    case centimeters
    case inches

    var id: String { rawValue }

    var symbol: String {
        self == .centimeters ? "cm" : "in"
    }

    func meters(_ value: Double) -> Double {
        self == .centimeters ? value / 100 : value * 0.0254
    }

    func display(_ meters: Double) -> Double {
        self == .centimeters ? meters * 100 : meters / 0.0254
    }
}

func validLength(_ value: Double) -> Bool {
    value.isFinite && value > 0
}

enum ProfileValidationError: Error {
    case incompleteBody
    case incompleteGarment
    case invalidOptionalWaist
}

struct Measurement: Codable, Equatable, Identifiable {
    var id = UUID()
    var key: MeasurementKey
    var meters: Double
    var confidence: Double?

    var centimeters: Double { meters * 100 }
}
