import Foundation
import Observation
import OSLog

@MainActor @Observable
final class TryOnModel {
  private(set) var result: TryOnResult?
  private(set) var stage = "Opening your scans…"
  private(set) var failure: String?
  private let builder = TryOnBuilder()
  private var generation = UUID()

  func load(avatar: AvatarScanAsset, garment: ClosetGarment, photoURL: URL) async {
    let token = UUID()
    generation = token
    result = nil; failure = nil
    guard let dimensions = garment.dimensions, dimensions.isValid else { failure = TryOnError.shirt.localizedDescription; return }
    do {
      let built = try await builder.build(avatar: avatar, dimensions: dimensions, photoURL: photoURL) { [weak self] stage in
        await self?.update(stage: stage, token: token)
      }
      try Task.checkCancellation()
      guard generation == token else { return }
      result = built
      Logger(subsystem: "app.onyou", category: "TryOn").info("Try-on ready; vertices: \(built.shape.mesh.positions.count); triangles: \((built.shape.mesh.front.count + built.shape.mesh.back.count) / 3)")
    } catch is CancellationError { }
    catch {
      guard generation == token, !Task.isCancelled else { return }
      failure = (error as? TryOnError)?.localizedDescription ?? "The preview couldn’t be opened. Your scans are unchanged. Try again."
      Logger(subsystem: "app.onyou", category: "TryOn").error("Try-on failed: \(error.localizedDescription, privacy: .private)")
    }
  }

  func cancel() { generation = UUID() }
  private func update(stage: String, token: UUID) { if generation == token { self.stage = stage } }
}
