import Foundation

enum BodyScanTiming {
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
