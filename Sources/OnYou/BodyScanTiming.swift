import OSLog

enum BodyScanTiming {
  enum Stage: String, CaseIterable {
    case framing, selection, bodyPass, passCheckpoint, detailPass, captureFinalization, photoPreflight, reconstruction, textureValidation, avatarLoading
  }

  private static let logger = Logger(subsystem: "app.onyou", category: "BodyScanTiming")

  static func seconds(for duration: Duration) -> Double {
    let components = duration.components
    return max(0, Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000)
  }

  static func record(_ stage: Stage, duration: Duration) {
    logger.info("Stage duration: \(stage.rawValue, privacy: .public); seconds: \(Self.seconds(for: duration), privacy: .public)")
  }
  static func buildProgress(current: Double, fraction: Double) -> Double? {
    guard fraction.isFinite else { return nil }
    return max(current, min(0.99, max(0, fraction)))
  }


  static func remaining(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds > 0 else { return "Estimating time remaining…" }
    if seconds < 45 { return "Almost ready" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .spellOut
    formatter.allowedUnits = seconds < 3600 ? [.minute] : [.hour, .minute]
    formatter.maximumUnitCount = 1
    let rounded = ceil(seconds / 60) * 60
    return formatter.string(from: rounded).map { "About \($0) remaining" } ?? "Building your avatar…"
  }

  static func elapsed(since start: Date, now: Date) -> String {
    let seconds = max(0, now.timeIntervalSince(start))
    guard seconds.isFinite else { return "Capture in progress" }
    if seconds < 10 { return "Just started" }
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .spellOut
    formatter.allowedUnits = seconds < 60 ? [.second] : [.minute]
    formatter.maximumUnitCount = 1
    return formatter.string(from: floor(seconds)).map { "\($0) elapsed" } ?? "Capture in progress"
  }
}
