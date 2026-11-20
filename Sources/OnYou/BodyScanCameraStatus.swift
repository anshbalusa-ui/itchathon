import Foundation

struct BodyScanCameraStatus: Equatable {
  enum Mode: Equatable { case initializing, framing, capturing, finishing }
  var mode: Mode
  var calibrated = false
  var calibrationProgress = 0.0
  var pendingStart = false
  var observedAt: TimeInterval?
  var completedViews: Set<BodyCaptureView> = []
  var missingAngles: [Double] = []
  var direction = 1
  var instruction = "Fit the person from head to toe."

  func canStart(now: TimeInterval) -> Bool {
    guard mode == .framing, calibrated, !pendingStart, let observedAt else { return false }
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
