import Foundation
import Observation

@MainActor @Observable
final class OnYouStore {
  private(set) var current: BodyMeasurements?
  private(set) var history: [BodySnapshot] = []
  var storageError: String?
  private let defaults: UserDefaults
  private let key = "on-you.measurements.v1"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    guard let data = defaults.data(forKey: key) else { return }
    do {
      let saved = try JSONDecoder().decode(SavedMeasurements.self, from: data)
      guard saved.current?.isValid != false,
            saved.history.allSatisfy({ $0.measurements.isValid }) else {
        throw CocoaError(.coderReadCorrupt)
      }
      current = saved.current
      history = saved.history
    } catch {
      storageError = "Saved measurements couldn’t be opened. The stored data has been kept."
    }
  }

  @discardableResult
  func save(_ measurements: BodyMeasurements) -> Bool {
    guard measurements.isValid else {
      storageError = "Check your measurements before saving."
      return false
    }
    guard measurements != current else { return true }
    let records = [BodySnapshot(measurements: measurements)] + history
    guard persist(current: measurements, history: records) else { return false }
    current = measurements
    history = records
    return true
  }

  func delete(_ offsets: IndexSet) {
    let records = history.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    guard persist(current: current, history: records) else { return }
    history = records
  }

  private func persist(current: BodyMeasurements?, history: [BodySnapshot]) -> Bool {
    do {
      let data = try JSONEncoder().encode(SavedMeasurements(current: current, history: history))
      defaults.set(data, forKey: key)
      return true
    } catch {
      storageError = "Measurements couldn’t be saved. Please try again."
      return false
    }
  }
}

struct BodySnapshot: Identifiable, Codable {
  var id = UUID()
  var date = Date()
  var measurements: BodyMeasurements
}

private struct SavedMeasurements: Codable {
  var current: BodyMeasurements?
  var history: [BodySnapshot]
}
