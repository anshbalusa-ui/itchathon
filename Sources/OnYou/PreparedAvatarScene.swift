@preconcurrency import SceneKit
import Foundation

/// An unattached, immutable scene prototype. Only clones are handed to render
/// owners; no view, camera, delegate, or task is retained. SceneKit materials and
/// geometry are shared read-only, never mutated after this object is published.
final class PreparedAvatarScene: @unchecked Sendable {
  struct LoadTimings: Sendable {
    var validation: Duration
    var scene: Duration
  }
  let calibration: AvatarScanCalibration
  let loadTimings: LoadTimings?
  private let prototype: SCNNode

  init(node: SCNNode,calibration: AvatarScanCalibration,loadTimings: LoadTimings? = nil) {
    prototype = node; self.calibration = calibration; self.loadTimings = loadTimings
  }
  func makeNode() -> SCNNode { prototype.clone() }

  /// Hash/file admission and native USDZ/texture inspection stay off the UI
  /// actor. Cancellation fences publication even when a native parse itself
  /// cannot be interrupted halfway through.
  static func load(url: URL,referenceHeightCM: Double? = nil) async throws -> PreparedAvatarScene {
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      let start = ContinuousClock.now
      _ = try AvatarScanStore.digest(url)
      let validated = ContinuousClock.now
      let loaded = try ScannedAvatarGeometry.load(url: url,referenceHeightCM: referenceHeightCM)
      let finished = ContinuousClock.now
      try Task.checkCancellation()
      return PreparedAvatarScene(node: loaded.node,calibration: loaded.calibration,
        loadTimings: LoadTimings(validation: start.duration(to: validated),scene: validated.duration(to: finished)))
    }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: { worker.cancel() }
  }
}
