import Foundation

struct ScanPositionFeedback: Equatable, Sendable {
  enum Direction: String, Sendable {
    case searching, closer, farther, left, right, up, down, level, hold
    var instruction: String {
      switch self {
      case .searching: "Finding the surface"
      case .closer: "Move closer"
      case .farther: "Move back"
      case .left: "Move left"
      case .right: "Move right"
      case .up: "Move toward the collar"
      case .down: "Move toward the hem"
      case .level: "Hold the iPhone more level"
      case .hold: "Good position · Hold steady"
      }
    }
    var symbol: String {
      switch self {
      case .closer, .down: "arrow.down"
      case .farther, .up: "arrow.up"
      case .left: "arrow.left"
      case .right: "arrow.right"
      case .hold: "checkmark"
      case .level: "iphone.radiowaves.left.and.right"
      case .searching: "viewfinder"
      }
    }
  }

  var meters: Double?
  var direction = Direction.searching
  var quality = 0.0
  var source = "Live surface distance"

  var intensity: Double { direction == .hold || direction == .searching ? 0 : max(0.15, min(1, 1 - quality)) }
  var distanceText: String {
    guard let meters, meters.isFinite, meters > 0 else { return "—" }
    return Foundation.Measurement(value: meters, unit: UnitLength.meters)
      .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
  }

  static func body(meters: Double?, capturedAt: Date?, now: Date, tooClose: Bool, tooFar: Bool, framed: Bool) -> Self {
    let fresh = capturedAt.map { (0...5).contains(now.timeIntervalSince($0)) } ?? false
    let valid = meters.map { $0.isFinite && (0.2...3).contains($0) } ?? false
    var position = Self(meters: fresh && valid ? meters : nil,
                        source: fresh && valid ? "Last captured photo · Not live" : "Waiting for a depth photo")
    if tooClose { position.direction = .farther }
    else if tooFar { position.direction = .closer }
    else if framed { position.direction = .hold; position.quality = 1 }
    return position
  }

  static func shirt(meters: Double?, target: Double, bounds: CGRect?, level: Double) -> Self {
    guard let meters, meters.isFinite, (0.2...3).contains(meters), target.isFinite, target > 0 else { return Self() }
    let ratio = meters / target
    let quality = max(0, 1 - abs(ratio - 1) / (ratio < 1 ? 0.6 : 0.8))
    var direction: Direction = ratio < 0.8 ? .farther : ratio > 1.25 ? .closer : .hold
    if let bounds {
      if bounds.width > 0.9 || bounds.height > 0.9 { direction = .farther }
      else if bounds.midX < 0.4 { direction = .left }
      else if bounds.midX > 0.6 { direction = .right }
      else if bounds.midY < 0.38 { direction = .up }
      else if bounds.midY > 0.62 { direction = .down }
    }
    if !level.isFinite || level < 0.90 { direction = .level }
    return Self(meters: meters, direction: direction, quality: direction == .hold ? quality : min(0.6, quality))
  }
}
