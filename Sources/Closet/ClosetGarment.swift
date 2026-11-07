import Foundation

struct ClosetGarment: Identifiable, Codable, Equatable {
  var id = UUID()
  var name: String
  var date = Date()
  var dimensions: GarmentScanDimensions?
  var productURL: URL?
  var isReference = false
  var imageID: UUID? = nil

  var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && name.count <= 120 && dimensions?.isValid != false
      && (productURL.map { Self.productLink($0.absoluteString) != nil } ?? true)
  }

  static func productLink(_ text: String) -> URL? {
    guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          components.scheme?.lowercased() == "https", let host = components.host, host.contains("."),
          components.user == nil, components.password == nil else { return nil }
    return components.url
  }
}

struct GarmentScanDimensions: Codable, Equatable, Sendable {
  var bodyWidthM: Double
  var lengthM: Double
  var sleeveSpanM: Double

  var isValid: Bool {
    [bodyWidthM, lengthM, sleeveSpanM].allSatisfy(\.isFinite)
      && (0.18...1).contains(bodyWidthM) && (0.25...1.5).contains(lengthM)
      && (0.25...1.7).contains(sleeveSpanM) && sleeveSpanM > bodyWidthM * 1.15
  }

  func agrees(with other: Self) -> Bool {
    guard isValid, other.isValid else { return false }
    return zip([bodyWidthM, lengthM, sleeveSpanM], [other.bodyWidthM, other.lengthM, other.sleeveSpanM])
      .allSatisfy { abs($0 - $1) <= max(0.015, $0 * 0.03) }
  }

  static func consensus(_ samples: [Self]) -> Self? {
    guard samples.count == 3, samples.allSatisfy(\.isValid),
          samples.allSatisfy({ a in samples.allSatisfy { a.agrees(with: $0) } }) else { return nil }
    return Self(bodyWidthM: samples.map(\.bodyWidthM).sorted()[1],
                lengthM: samples.map(\.lengthM).sorted()[1],
                sleeveSpanM: samples.map(\.sleeveSpanM).sorted()[1])
  }

  func comparison(to reference: Self) -> [(String, String)] {
    func describe(_ value: Double, _ base: Double, less: String, more: String) -> String {
      let difference = value - base
      if abs(difference) <= max(0.02, base * 0.04) { return "Similar" }
      return difference < 0 ? less : more
    }
    return [
      ("Body", describe(bodyWidthM, reference.bodyWidthM, less: "Narrower", more: "Wider")),
      ("Length", describe(lengthM, reference.lengthM, less: "Shorter", more: "Longer")),
      ("Sleeves", describe(sleeveSpanM, reference.sleeveSpanM, less: "Less reach", more: "More reach"))
    ]
  }
}

enum GarmentCaptureError: LocalizedError {
  case unclear, framing, shape, depth, angle, interrupted, image, storage

  var errorDescription: String? {
    switch self {
    case .unclear: "Place just the shirt on a plain, contrasting surface. Spread the sleeves and smooth out folds."
    case .framing: "Keep the whole shirt in view with clear space around every edge. Point the collar toward the top of the screen."
    case .shape: "Use a short-sleeved shirt, laid flat with the collar at the top and sleeves spread. Try a clearer background."
    case .depth: "Depth isn’t clear enough. Use even indoor light and hold still above the shirt."
    case .angle: "Hold the phone flat, directly above a horizontal surface. Keep the entire shirt visible."
    case .interrupted: "Capture was interrupted. Return to the camera and try again."
    case .image: "This image couldn’t be opened. Choose a clear photo of the garment."
    case .storage: "Your closet couldn’t be saved. Your existing items have been kept."
    }
  }
}
