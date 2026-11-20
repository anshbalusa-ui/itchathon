import Foundation

struct ScanPositionFeedback: Equatable, Sendable {
  enum Direction: String, Sendable {
    case searching, closer, farther, left, right, up, down, level, hold

    var instruction: String {
      switch self {
      case .searching: "Finding the subject"
      case .closer: "Move closer"
      case .farther: "Move back"
      case .left: "Aim left"
      case .right: "Aim right"
      case .up: "Aim higher"
      case .down: "Aim lower"
      case .level: "Level the iPhone"
      case .hold: "In safe range · Hold steady"
      }
    }

    var symbol: String {
      switch self {
      case .closer: "arrow.down"
      case .farther: "arrow.up"
      case .left: "arrow.left"
      case .right: "arrow.right"
      case .up: "arrow.up"
      case .down: "arrow.down"
      case .hold: "checkmark"
      case .level: "iphone.radiowaves.left.and.right"
      case .searching: "viewfinder"
      }
    }
  }

  var meters: Double?
  var direction = Direction.searching
  var severity = 0.0
  var source = "Live LiDAR distance"
  var observedAt: TimeInterval?

  var intensity: Double {
    guard direction != .hold, direction != .searching, severity.isFinite else { return 0 }
    return min(1, max(0, severity))
  }
  var quality: Double {
    direction == .searching ? 0 : 1 - min(1, max(0, severity.isFinite ? severity : 1))
  }
  var distanceText: String {
    guard let meters, meters.isFinite, meters > 0 else { return "—" }
    return Foundation.Measurement(value: meters, unit: UnitLength.meters)
      .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1))))
  }
}
