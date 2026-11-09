import CryptoKit
import Foundation
import Observation

@MainActor @Observable
final class AvatarScanStore {
  private(set) var asset: AvatarScanAsset?
  private(set) var hasUnreadableScan = false
  var error: String?
  private let root: URL
  private var manifest: URL { root.appendingPathComponent("active.json") }

  init(directory: URL? = nil) {
    root = directory ?? URL.applicationSupportDirectory.appendingPathComponent("OnYouScans", isDirectory: true)
    do {
      try Self.prepareDirectory(root)
      if FileManager.default.fileExists(atPath: manifest.path) {
        let record = try JSONDecoder().decode(AvatarScanRecord.self, from: Data(contentsOf: manifest))
        let url = modelURL(record.id)
        guard record.isValid, try Self.digest(url) == record.sha256 else { throw AvatarScanError.invalidModel }
        asset = AvatarScanAsset(record: record, url: url)
      }
      // Only our UUID-named abandoned attempts are removed, after loading the active record.
      for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
        if let id = UUID(uuidString: url.lastPathComponent), id != asset?.record.id {
          try? FileManager.default.removeItem(at: url)
        }
      }
    } catch {
      hasUnreadableScan = FileManager.default.fileExists(atPath: manifest.path)
      self.error = "Your saved scan couldn’t be opened. Its files have been kept. \(error.localizedDescription)"
    }
  }

  func save(model: URL, calibration: AvatarScanCalibration, imageCount: Int, completedPasses: Int) throws {
    try calibration.validate()
    let verified = try ScannedAvatarGeometry.load(url: model, referenceHeightCM: calibration.usesDepthScale ? nil : calibration.referenceHeightCM)
    guard verified.calibration == calibration else { throw AvatarScanError.invalidModel }
    let id = UUID()
    let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
    try Self.prepareDirectory(directory)
    do {
      let destination = modelURL(id)
      try FileManager.default.copyItem(at: model, to: destination)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
      let record = AvatarScanRecord(id: id, date: Date(), referenceHeightCM: calibration.referenceHeightCM,
                                    capturedHeightM: calibration.size.y, widthM: calibration.size.x, depthM: calibration.size.z,
                                    imageCount: imageCount, completedPasses: completedPasses, sha256: try Self.digest(destination), usesDepthScale: calibration.usesDepthScale)
      guard record.isValid else { throw AvatarScanError.insufficientCoverage }
      let data = try JSONEncoder().encode(record)
      try data.write(to: manifest, options: [.atomic, .completeFileProtection])
      let previous = asset
      asset = AvatarScanAsset(record: record, url: destination)
      hasUnreadableScan = false
      if let previous { try? FileManager.default.removeItem(at: previous.url.deletingLastPathComponent()) }
    } catch {
      try? FileManager.default.removeItem(at: directory)
      throw error
    }
  }

  func delete() {
    do {
      for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        where UUID(uuidString: url.lastPathComponent) != nil {
        try FileManager.default.removeItem(at: url)
      }
      if FileManager.default.fileExists(atPath: manifest.path) { try FileManager.default.removeItem(at: manifest) }
      asset = nil
      hasUnreadableScan = false
    } catch {
      self.error = "The scan couldn’t be fully deleted. \(error.localizedDescription)"
    }
  }

  private func modelURL(_ id: UUID) -> URL {
    root.appendingPathComponent(id.uuidString).appendingPathComponent("avatar.usdz")
  }

  static func prepareDirectory(_ directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                          attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
    var url = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  nonisolated static func digest(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          let size = values.fileSize, (1...256_000_000).contains(size) else { throw AvatarScanError.invalidModel }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
}
