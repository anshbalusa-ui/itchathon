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
  private var work: Task<TryOnResult, Error>?

  func load(avatar: AvatarScanAsset, garment: ClosetGarment, photoURL: URL) async {
    work?.cancel()
    let token = UUID()
    generation = token
    result = nil; failure = nil
    guard let dimensions = garment.dimensions, dimensions.isValid else { failure = TryOnError.missingDimensions.localizedDescription; return }
    let owner = builder
    let job = Task { [weak self] in
      try await owner.build(avatar: avatar, garment: garment, photoURL: photoURL) { [weak self] stage in
        await self?.update(stage: stage, token: token)
      }
    }
    work = job
    defer { if generation == token { work = nil } }
    do {
      let built = try await withTaskCancellationHandler {
        try await job.value
      } onCancel: { job.cancel() }
      try Task.checkCancellation()
      guard generation == token else { return }
      result = built
      Logger(subsystem: "app.onyou", category: "TryOn").info("Preview ready; preparation milliseconds: \(built.timings.totalMS, privacy: .public)")
    } catch is CancellationError { }
    catch {
      guard generation == token, !Task.isCancelled else { return }
      failure = (error as? TryOnError)?.localizedDescription ?? "The preview couldn’t be opened. Your scans are unchanged. Try again."
      Logger(subsystem: "app.onyou", category: "TryOn").error("Preview preparation failed. Saved inputs unchanged.")
    }
  }

  func cancel() {
    generation = UUID(); result = nil; failure = nil
    work?.cancel(); work = nil
    let owner = builder
    Task { await owner.clear() }
  }
  private func update(stage: String, token: UUID) { if generation == token { self.stage = stage } }
}
