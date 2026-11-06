import Foundation

struct BodyMeasurements: Codable, Equatable, Sendable {
  var height: Double = 175
  var chest: Double = 96
  var waist: Double = 80
  var hips: Double = 98
  var shoulders: Double = 44

  static var example: Self { Self() }

  subscript(_ field: BodyMeasurementField) -> Double {
    get {
      switch field {
      case .height: height
      case .chest: chest
      case .waist: waist
      case .hips: hips
      case .shoulders: shoulders
      }
    }
    set {
      switch field {
      case .height: height = newValue
      case .chest: chest = newValue
      case .waist: waist = newValue
      case .hips: hips = newValue
      case .shoulders: shoulders = newValue
      }
    }
  }

  var isValid: Bool {
    BodyMeasurementField.allCases.allSatisfy { self[$0].isFinite && $0.range.contains(self[$0]) }
  }

  static func parse(_ fields: [BodyMeasurementField: String], unit: BodyMeasurementUnit, locale: Locale = .current) -> Self? {
    var result = Self.example
    for field in BodyMeasurementField.allCases {
      let text = (fields[field] ?? "").trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
      guard let value = Double(text), value.isFinite else { return nil }
      result[field] = (value * unit.centimeters * 10).rounded() / 10
    }
    return result.isValid ? result : nil
  }
}

enum BodyMeasurementUnit: String, CaseIterable, Identifiable {
  case centimeters, inches
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var symbol: String { self == .centimeters ? "cm" : "in" }
  var centimeters: Double { self == .centimeters ? 1 : 2.54 }
}

enum BodyMeasurementField: String, CaseIterable, Identifiable, Codable {
  case height, chest, waist, hips, shoulders
  var id: String { rawValue }
  var title: String { rawValue.capitalized }
  var range: ClosedRange<Double> {
    switch self {
    case .height: 120...220
    case .chest: 60...170
    case .waist: 45...170
    case .hips: 65...180
    case .shoulders: 28...65
    }
  }
  var instruction: String {
    switch self {
    case .height: "Stand barefoot against a wall. Measure from the floor to the top of your head."
    case .chest: "Wrap the tape around the fullest part of your chest. Keep it level and breathe normally."
    case .waist: "Measure around your natural waist, between your lowest rib and the top of your hips. Keep the tape snug without pulling it tight."
    case .hips: "Stand with your feet together. Measure around the widest part of your hips and seat."
    case .shoulders: "Measure across your back from the outer edge of one shoulder bone to the other. This is a width, not a circumference."
    }
  }
}
