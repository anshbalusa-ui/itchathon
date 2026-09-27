import Combine
import Foundation

@MainActor
final class ProfileStore: ObservableObject {
  @Published private(set) var bodyProfile: BodyProfile
  @Published private(set) var preferredGarment: GarmentProfile?
  @Published private(set) var currentGarment: GarmentProfile
  @Published private(set) var currentSizeChart: GarmentSizeChart?
  @Published private(set) var lastReport: FitReport?
  @Published private(set) var sizeComparison: SizeComparisonReport?

  private enum Key {
    // Keep the original key so existing body measurements survive this update.
    static let body = "fitcheck.bodyProfile"
    static let preferred = "fitcheck.preferredGarment"
    static let candidate = "fitcheck.currentGarment"
    static let chart = "fitcheck.currentSizeChart"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    bodyProfile = Self.load(BodyProfile.self, key: Key.body, from: defaults) ?? BodyProfile()
    preferredGarment = Self.load(GarmentProfile.self, key: Key.preferred, from: defaults)
    currentGarment = Self.load(GarmentProfile.self, key: Key.candidate, from: defaults) ?? GarmentProfile()
    currentSizeChart = Self.load(GarmentSizeChart.self, key: Key.chart, from: defaults)
  }

  func saveBody(_ draft: BodyProfile) throws {
    guard draft.isUsable else { throw FitInputError.incompleteBody }
    var saved = draft
    saved.updatedAt = .now
    try persist(saved, key: Key.body)
    bodyProfile = saved
    invalidateReports()
  }

  func saveGarment(_ draft: GarmentProfile, role: GarmentRole) throws {
    guard draft.isUsable,
          !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FitInputError.incompleteGarment
    }
    guard draft.category == .tshirt else { throw FitInputError.unsupportedCategory }
    switch role {
    case .preferred:
      try persist(draft, key: Key.preferred)
      preferredGarment = draft
    case .candidate:
      try persist(draft, key: Key.candidate)
      currentGarment = draft
    }
    invalidateReports()
  }

  func saveSizeChart(_ chart: GarmentSizeChart) throws {
    guard chart.measurementBasis == .finishedGarment,
          chart.category == .tshirt,
          !chart.garmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let source = chart.sourceNote,
          !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !chart.sizes.isEmpty else {
      throw FitInputError.invalidChart
    }
    let labels = chart.sizes.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
    guard labels.allSatisfy({ !$0.isEmpty }), Set(labels).count == labels.count,
          chart.sizes.allSatisfy({ size in
            size.chestFlat.isFinite && size.chestFlat > 0
              && size.shoulderWidth.isFinite && size.shoulderWidth > 0
              && size.length.isFinite && size.length > 0
              && size.waistFlat.isFinite && size.waistFlat >= 0
          }) else {
      throw FitInputError.invalidChart
    }
    try persist(chart, key: Key.chart)
    currentSizeChart = chart
    sizeComparison = nil
  }

  func evaluateCurrentGarment() throws {
    lastReport = nil
    guard let preferredGarment else { throw FitInputError.incompleteGarment }
    lastReport = try FitEngine.evaluate(
      body: bodyProfile,
      preferred: preferredGarment,
      garment: currentGarment
    )
  }

  func evaluateAvailableSizes() throws {
    sizeComparison = nil
    guard let preferredGarment else { throw FitInputError.incompleteGarment }
    guard let currentSizeChart else { throw FitInputError.invalidChart }
    sizeComparison = try FitEngine.evaluateSizes(
      body: bodyProfile,
      preferred: preferredGarment,
      chart: currentSizeChart
    )
  }

  func deleteMeasurements() {
    for key in [Key.body, Key.preferred, Key.candidate, Key.chart] {
      defaults.removeObject(forKey: key)
    }
    bodyProfile = BodyProfile()
    preferredGarment = nil
    currentGarment = GarmentProfile()
    currentSizeChart = nil
    invalidateReports()
  }

  private func invalidateReports() {
    lastReport = nil
    sizeComparison = nil
  }

  private func persist<Value: Encodable>(_ value: Value, key: String) throws {
    defaults.set(try JSONEncoder().encode(value), forKey: key)
  }

  private static func load<Value: Decodable>(
    _ type: Value.Type,
    key: String,
    from defaults: UserDefaults
  ) -> Value? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}
