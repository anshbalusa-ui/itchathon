import Foundation

struct BodyScanCameraStatus: Equatable {
  enum Mode: Equatable { case initializing, framing, capturing, finishing }
  enum StartState: Equatable {
    case idle, countdown(Int), waitingForFraming, starting
  }
  var mode: Mode
  var calibrated = false
  var calibrationProgress = 0.0
  var start = StartState.idle
  var observedAt: TimeInterval?
  var completedViews: Set<BodyCaptureView> = []
  var missingAngles: [Double] = []
  var direction = 1
  var instruction = "Keep your head and feet visible."

  var pendingStart: Bool { start != .idle }
  var canArmStart: Bool { mode == .framing && start == .idle }
  var canCancelStart: Bool {
    switch start {
    case .countdown, .waitingForFraming: mode == .framing
    case .idle, .starting: false
    }
  }

  var countdown: Int? {
    if case .countdown(let seconds) = start { return seconds }
    return nil
  }

  func canStart(now: TimeInterval) -> Bool {
    start == .waitingForFraming && hasFreshCalibration(now: now)
  }

  func hasFreshCalibration(now: TimeInterval) -> Bool {
    guard mode == .framing, calibrated, let observedAt else { return false }
    return (0...0.6).contains(now - observedAt)
  }

  var neededView: BodyCaptureView? {
    guard let angle = missingAngles.first else { return nil }
    return BodyCaptureView.nearest(to: angle, direction: direction)
  }

  var viewsAccessibilityValue: String {
    let captured = BodyCaptureView.allCases.filter { completedViews.contains($0) && $0 != neededView }.map(\.title)
    let summary = captured.isEmpty ? "No views captured." : "\(ListFormatter.localizedString(byJoining: captured)) captured."
    guard let neededView else { return summary }
    return "\(summary) \(neededView.title) needed."
  }
}
