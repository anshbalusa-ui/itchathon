import Foundation
import Observation
import UIKit

@MainActor @Observable
final class ClosetStore {
  private(set) var garments: [ClosetGarment] = []
  var error: String?
  private let root: URL
  private var manifest: URL { root.appendingPathComponent("closet.json") }
  private var unreadable = false

  init(directory: URL? = nil) {
    root = directory ?? URL.applicationSupportDirectory.appendingPathComponent("OnYouCloset", isDirectory: true)
    do {
      try AvatarScanStore.prepareDirectory(root)
      if FileManager.default.fileExists(atPath: manifest.path) {
        let saved = try JSONDecoder().decode([ClosetGarment].self, from: Data(contentsOf: manifest))
        guard saved.allSatisfy(\.isValid), Set(saved.map(\.id)).count == saved.count,
              saved.filter(\.isReference).count <= 1 else { throw GarmentCaptureError.storage }
        garments = saved
      }
    } catch {
      unreadable = true
      self.error = "Your closet couldn’t be opened. Its files have been kept."
    }
  }

  var reference: ClosetGarment? { garments.first(where: \.isReference) }
  func imageURL(for garment: ClosetGarment) -> URL { root.appendingPathComponent((garment.imageID ?? garment.id).uuidString + ".png") }
  func hasPhoto(for garment: ClosetGarment) -> Bool { FileManager.default.isReadableFile(atPath: imageURL(for: garment).path) }

  @discardableResult
  func add(name: String, image: Data, dimensions: GarmentScanDimensions?, productURL: URL?, pattern: GarmentPatternEvidence? = nil) throws -> ClosetGarment {
    guard !unreadable, image.count <= 20_000_000, UIImage(data: image) != nil,
          pattern?.matches(image) != false else { throw GarmentCaptureError.storage }
    let garment = ClosetGarment(name: name.trimmingCharacters(in: .whitespacesAndNewlines), dimensions: dimensions, productURL: productURL, pattern: pattern)
    guard garment.isValid else { throw GarmentCaptureError.storage }
    let file = imageURL(for: garment)
    try image.write(to: file, options: [.atomic, .completeFileProtection])
    do {
      try persist([garment] + garments)
    } catch {
      try? FileManager.default.removeItem(at: file)
      throw error
    }
    return garment
  }

  func replaceCapture(for garment: ClosetGarment, with capture: GarmentCaptureResult) throws {
    guard let index = garments.firstIndex(where: { $0.id == garment.id }), !unreadable,
          capture.dimensions.isValid, capture.image.count <= 20_000_000,
          UIImage(data: capture.image) != nil, capture.pattern?.matches(capture.image) != false else { throw GarmentCaptureError.storage }
    var items = garments
    let previous = imageURL(for: items[index])
    items[index].imageID = UUID()
    items[index].dimensions = capture.dimensions
    items[index].pattern = capture.pattern
    let destination = imageURL(for: items[index])
    try capture.image.write(to: destination, options: [.atomic, .completeFileProtection])
    do { try persist(items) }
    catch { try? FileManager.default.removeItem(at: destination); throw error }
    try? FileManager.default.removeItem(at: previous)
  }

  func setReference(_ garment: ClosetGarment) {
    guard garments.contains(where: { $0.id == garment.id }), garment.dimensions != nil else { return }
    var items = garments
    for index in items.indices { items[index].isReference = items[index].id == garment.id }
    do { try persist(items) } catch { self.error = error.localizedDescription }
  }

  func delete(_ garment: ClosetGarment) {
    do {
      try persist(garments.filter { $0.id != garment.id })
      let file = imageURL(for: garment)
      if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    } catch { self.error = error.localizedDescription }
  }

  private func persist(_ items: [ClosetGarment]) throws {
    guard !unreadable, items.allSatisfy(\.isValid) else { throw GarmentCaptureError.storage }
    try JSONEncoder().encode(items).write(to: manifest, options: [.atomic, .completeFileProtection])
    garments = items
  }
}
