@preconcurrency import SceneKit
import CryptoKit
import UIKit

struct TryOnTimings: Sendable, Encodable {
  var avatarLoadMS = 0.0
  var surfaceExtractionMS = 0.0
  var poseMS = 0.0
  var photoMS = 0.0
  var recognitionMS = 0.0
  var landmarkPredictionMS = 0.0
  var meshMS = 0.0
  var sceneMS = 0.0
  var totalMS = 0.0
  var usedCapturedLandmarks = false
  var avatarCacheHit = false
  var patternCacheHit = false
  var preparedSceneCacheHit = false
}

struct TryOnResult: Sendable, Identifiable {
  var id = UUID()
  var shape: TryOnShape
  var bodyYaw: Float
  var avatar: PreparedAvatarScene
  var garment: TryOnPreparedGarment
  var timings: TryOnTimings
}

/// Bounded one-avatar/one-pattern/one-ready-scene caches for this presentation.
/// Immutable scene templates contain no view, camera, task or coordinator.
actor TryOnBuilder {
  private struct AvatarKey: Equatable {
    var id: UUID
    var sha256: String
    var height: Double
    var url: URL
  }
  private struct AvatarCache {
    var key: AvatarKey
    var template: PreparedAvatarScene
    var solution: TryOnPoseSolution
  }
  private struct PatternCache {
    var key: String
    var pattern: TryOnPattern
    var image: CGImage
    var evidence: GarmentPatternEvidence?
  }
  private var avatarCache: AvatarCache?
  private var patternCache: PatternCache?
  private struct SceneKey: Equatable {
    var avatar: AvatarKey
    var garmentID: UUID
    var imageID: UUID?
    var photoSHA256: String
    var dimensions: GarmentScanDimensions
    var evidence: GarmentPatternEvidence?
  }
  private var sceneCache: (key: SceneKey,value: TryOnResult)?

  func clear() { avatarCache = nil; patternCache = nil; sceneCache = nil }

  func build(avatar: AvatarScanAsset, garment: ClosetGarment, photoURL: URL,
             progress: @Sendable (String) async -> Void) async throws -> TryOnResult {
    let started = ProcessInfo.processInfo.systemUptime
    var timings = TryOnTimings()
    try Task.checkCancellation()
    guard avatar.record.isValid else { throw TryOnError.body }
    guard let dimensions = garment.dimensions, dimensions.isValid else { throw TryOnError.missingDimensions }
    await progress("Opening your saved avatar…")
    let loadStarted = ProcessInfo.processInfo.systemUptime
    // Cache reuse never bypasses the saved artifact's integrity check.
    guard (try? AvatarScanStore.digest(avatar.url)) == avatar.record.sha256 else { throw TryOnError.body }
    let avatarKey = AvatarKey(id: avatar.record.id,sha256: avatar.record.sha256,
      height: avatar.record.referenceHeightCM,url: avatar.url.standardizedFileURL)
    let prepared: AvatarCache
    if let cached = avatarCache, cached.key == avatarKey {
      prepared = cached; timings.avatarCacheHit = true
      timings.avatarLoadMS = (ProcessInfo.processInfo.systemUptime - loadStarted) * 1000
    } else {
      let loaded = try ScannedAvatarGeometry.load(url: avatar.url, referenceHeightCM: avatar.record.referenceHeightCM)
      timings.avatarLoadMS = (ProcessInfo.processInfo.systemUptime - loadStarted) * 1000
      try Task.checkCancellation()
      await progress("Locating the observed shoulders and arms…")
      let extractionStarted = ProcessInfo.processInfo.systemUptime
      let mesh = try TryOnSurface.extract(loaded.node)
      timings.surfaceExtractionMS = (ProcessInfo.processInfo.systemUptime - extractionStarted) * 1000
      let poseStarted = ProcessInfo.processInfo.systemUptime
      let solution = try TryOnPoseEstimator.solve(mesh: mesh)
      try Task.checkCancellation()
      prepared = AvatarCache(key: avatarKey, template: PreparedAvatarScene(node: loaded.node,calibration: loaded.calibration), solution: solution)
      avatarCache = prepared
      timings.poseMS = (ProcessInfo.processInfo.systemUptime - poseStarted) * 1000
    }
    try Task.checkCancellation()
    await progress("Opening the shirt capture…")
    let photoStarted = ProcessInfo.processInfo.systemUptime
    let photo: Data
    do {
      let attributes = try photoURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
            let count = attributes.fileSize, (1...20_000_000).contains(count) else { throw TryOnError.missingPhoto }
      photo = try Data(contentsOf: photoURL, options: .mappedIfSafe)
    } catch { throw TryOnError.missingPhoto }
    let photoKey = SHA256.hash(data: photo).map { String(format: "%02x", $0) }.joined()
    if let evidence = garment.pattern, !evidence.matches(photo) { throw TryOnError.shirt }
    timings.photoMS = (ProcessInfo.processInfo.systemUptime - photoStarted) * 1000
    let sceneKey = SceneKey(avatar: avatarKey,garmentID: garment.id,imageID: garment.imageID,
      photoSHA256: photoKey,dimensions: dimensions,evidence: garment.pattern)
    if let cached = sceneCache,cached.key == sceneKey {
      try Task.checkCancellation()
      timings.preparedSceneCacheHit = true
      timings.usedCapturedLandmarks = cached.value.timings.usedCapturedLandmarks
      timings.totalMS = (ProcessInfo.processInfo.systemUptime-started)*1000
      var ready = cached.value
      ready.id = UUID(); ready.timings = timings
      return ready
    }
    let pattern: PatternCache
    if let cached = patternCache, cached.key == photoKey, cached.evidence == garment.pattern {
      pattern = cached; timings.patternCacheHit = true
      timings.usedCapturedLandmarks = garment.pattern != nil
    } else {
      let recognizeStarted = ProcessInfo.processInfo.systemUptime
      let image: CGImage
      do { image = try GarmentImageProcessor.normalized(photo) } catch { throw TryOnError.missingPhoto }
      let points: [CGPoint]
      if let evidence = garment.pattern {
        // The exact-photo binding was checked even on cache hits above.
        points = evidence.points.map(\.point)
        timings.usedCapturedLandmarks = true
      } else {
        // Existing scans predate retained observations. Recognize their actual
        // saved image, once; never substitute a generic shirt after failure.
        await progress("Reading the saved shirt outline…")
        do {
          let detected = try await GarmentLandmarkService.shared.detect(in: image)
          points = detected.points
          timings.landmarkPredictionMS = detected.timing.predictionMS
        } catch is CancellationError { throw CancellationError() }
        catch { throw TryOnError.shirt }
      }
      try Task.checkCancellation()
      let mask = try Self.pattern(image, landmarks: points.map { SIMD2(Float($0.x), Float($0.y)) })
      pattern = PatternCache(key: photoKey, pattern: mask, image: image, evidence: garment.pattern)
      patternCache = pattern
      timings.recognitionMS = (ProcessInfo.processInfo.systemUptime - recognizeStarted) * 1000
    }
    try Task.checkCancellation()
    await progress("Draping the illustrative shirt shell…")
    let meshStarted = ProcessInfo.processInfo.systemUptime
    let shape = try TryOnGarmentShell.build(surface: prepared.solution.surface, pose: prepared.solution.pose, pattern: pattern.pattern, dimensions: dimensions)
    timings.meshMS = (ProcessInfo.processInfo.systemUptime - meshStarted) * 1000
    try Task.checkCancellation()
    await progress("Preparing the 3D preview…")
    let sceneStarted = ProcessInfo.processInfo.systemUptime
    let garmentScene = try TryOnPreparedGarment(mesh: shape.mesh, front: pattern.image, backColor: pattern.pattern.color)
    timings.sceneMS = (ProcessInfo.processInfo.systemUptime - sceneStarted) * 1000
    timings.totalMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
    try Task.checkCancellation()
    let ready = TryOnResult(shape: shape, bodyYaw: prepared.solution.yaw,
                           avatar: prepared.template, garment: garmentScene, timings: timings)
    sceneCache = (sceneKey,ready)
    return ready
  }

  static func pattern(_ image: CGImage, landmarks: [SIMD2<Float>]) throws -> TryOnPattern {
    guard image.width > 1, image.height > 1, landmarks.count == 25,
          landmarks.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw TryOnError.shirt }
    // The original photo remains the texture. Only the silhouette analysis is
    // downsampled, instead of scanning/sorting millions of RGBA samples.
    let scale = min(1, 384 / Double(max(image.width, image.height)))
    let width = max(2, Int(Double(image.width) * scale)), height = max(2, Int(Double(image.height) * scale))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let valid = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard valid else { throw TryOnError.shirt }
    var alpha = [UInt8](repeating: 0, count: width * height)
    var red: [Float] = [], green: [Float] = [], blue: [Float] = []
    let stride = max(1, width * height / 800)
    for i in 0..<(width * height) {
      alpha[i] = pixels[i * 4 + 3]
      if i % stride == 0 && pixels[i * 4 + 3] > 240 {
        red.append(Float(pixels[i * 4]) / 255); green.append(Float(pixels[i * 4 + 1]) / 255); blue.append(Float(pixels[i * 4 + 2]) / 255)
      }
    }
    guard red.count >= 20 else { throw TryOnError.shirt }
    let outline: GarmentOutline
    do { outline = try GarmentOutline.detect(mask: alpha, width: width, height: height)
      _ = try GarmentLandmarkValidation.validate(landmarks.map { CGPoint(x: Double($0.x), y: Double($0.y)) }, against: outline)
    } catch { throw TryOnError.shirt }
    red.sort(); green.sort(); blue.sort()
    let color = SIMD3(red[red.count / 2], green[green.count / 2], blue[blue.count / 2])
    return TryOnPattern(width: width, height: height, alpha: alpha, points: landmarks, color: color)
  }
}
