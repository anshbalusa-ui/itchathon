#if DEBUG
import SceneKit
import UIKit
import SwiftUI

/// Authored nonpersonal artifacts admitted by the same USDZ/closet contracts as
/// saved captures. Never runs during camera capture or writes to personal stores.
@MainActor
enum OnYouTryOnFixtures {
  struct Stores {
    var scans: AvatarScanStore
    var measurements: OnYouStore
    var closet: ClosetStore
    var root: URL
  }

  static let shirtPoints: [CGPoint] = [
    CGPoint(x: 0.50, y: 0.22), CGPoint(x: 0.42, y: 0.12), CGPoint(x: 0.40, y: 0.155),
    CGPoint(x: 0.43, y: 0.20), CGPoint(x: 0.57, y: 0.20), CGPoint(x: 0.58, y: 0.12),
    CGPoint(x: 0.20, y: 0.18), CGPoint(x: 0.12, y: 0.25), CGPoint(x: 0.04, y: 0.34),
    CGPoint(x: 0.095, y: 0.40), CGPoint(x: 0.15, y: 0.47), CGPoint(x: 0.28, y: 0.37),
    CGPoint(x: 0.27, y: 0.54), CGPoint(x: 0.26, y: 0.70), CGPoint(x: 0.25, y: 0.88),
    CGPoint(x: 0.50, y: 0.90), CGPoint(x: 0.75, y: 0.88), CGPoint(x: 0.74, y: 0.70),
    CGPoint(x: 0.73, y: 0.54), CGPoint(x: 0.72, y: 0.37), CGPoint(x: 0.85, y: 0.47),
    CGPoint(x: 0.905, y: 0.40), CGPoint(x: 0.96, y: 0.34), CGPoint(x: 0.88, y: 0.25),
    CGPoint(x: 0.80, y: 0.18)
  ]

  static func make(scenario: String = "valid", body: String = "a") throws -> Stores {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("OnYouSynthetic-" + UUID().uuidString, isDirectory: true)
    try AvatarScanStore.prepareDirectory(root)
    let scans = AvatarScanStore(directory: root.appendingPathComponent("avatars"))
    let closet = ClosetStore(directory: root.appendingPathComponent("closet"))
    guard let defaults = UserDefaults(suiteName: "OnYouSynthetic." + UUID().uuidString) else { throw CocoaError(.fileWriteUnknown) }
    let measurements = OnYouStore(defaults: defaults)
    if scenario != "missing-avatar" {
      let name = scenario == "unusable-pose" ? "unsupported-pose" : "synthetic-avatar-" + body
      guard let model = Bundle.main.url(forResource: name, withExtension: "usdz", subdirectory: "OnYouTryOnFixtures") else { throw AvatarScanError.invalidModel }
      let loaded = try ScannedAvatarGeometry.load(url: model)
      try scans.save(model: model, calibration: loaded.calibration, imageCount: 72, completedPasses: 2)
    }
    guard let imageURL = Bundle.main.url(forResource: "synthetic-shirt", withExtension: "png", subdirectory: "OnYouTryOnFixtures") else { throw GarmentCaptureError.image }
    let image = try Data(contentsOf: imageURL)
    let normalized = try GarmentImageProcessor.normalized(image)
    let pattern = try TryOnBuilder.pattern(normalized, landmarks: shirtPoints.map { SIMD2(Float($0.x), Float($0.y)) })
    let outline = try GarmentOutline.detect(mask: pattern.alpha, width: pattern.width, height: pattern.height)
    let evidence = try GarmentPatternEvidence.validate(image: image, points: shirtPoints, outline: outline)
    let first = try closet.add(name: "Fixture · Tide shirt", image: image,
      dimensions: scenario == "photo-only" ? nil : GarmentScanDimensions(bodyWidthM: 0.52, lengthM: 0.72, sleeveSpanM: 0.92),
      productURL: nil, pattern: scenario == "photo-only" ? nil : evidence)
    if scenario == "missing-photo" { try FileManager.default.removeItem(at: closet.imageURL(for: first)) }
    // A genuinely different captured image and physical-dimension fixture, not
    // an alternate label on the same cached result.
    guard let secondURL = Bundle.main.url(forResource: "synthetic-shirt-coral", withExtension: "png", subdirectory: "OnYouTryOnFixtures") else { throw GarmentCaptureError.image }
    let secondImage = try Data(contentsOf: secondURL)
    let secondEvidence = try GarmentPatternEvidence.validate(image: secondImage, points: shirtPoints, outline: outline)
    _ = try closet.add(name: "Fixture · Coral shirt", image: secondImage,
      dimensions: GarmentScanDimensions(bodyWidthM: 0.58, lengthM: 0.80, sleeveSpanM: 1.0), productURL: nil, pattern: secondEvidence)
    return Stores(scans: scans, measurements: measurements, closet: closet, root: root)
  }
}

struct OnYouFixtureRootView: View {
  @State private var stores: OnYouTryOnFixtures.Stores?
  @State private var failure: String?
  @State private var attempt = UUID()
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    Group {
      if let stores {
        VStack(spacing: 0) {
          Label(typeSize.isAccessibilitySize ? "Synthetic · Not a scan" : "Synthetic fixtures · Not a personal scan",systemImage: "testtube.2")
            .font(.caption.weight(.medium)).padding(8).frame(maxWidth: .infinity)
            .background(.bar).accessibilityIdentifier("onyou.synthetic")
          OnYouRootView(scans: stores.scans, closet: stores.closet, store: stores.measurements, synthetic: true)
        }
      } else if let failure {
        ContentUnavailableView {
          Label("Synthetic fixtures unavailable", systemImage: "exclamationmark.triangle")
        } description: { Text(failure) } actions: {
          Button("Retry fixture setup") { attempt = UUID() }
        }
      } else { ProgressView("Opening isolated synthetic fixtures…") }
    }
    .task(id: attempt) {
      do {
        let arguments = ProcessInfo.processInfo.arguments
        let scenario = arguments.first(where: { $0.hasPrefix("-onyou-fixture-scenario=") })?.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "valid"
        let body = arguments.contains("-onyou-fixture-body=b") ? "b" : "a"
        stores = try OnYouTryOnFixtures.make(scenario: scenario, body: body); failure = nil
      } catch { failure = error.localizedDescription }
    }
  }
}
#endif
