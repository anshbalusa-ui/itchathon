import Foundation

struct BodyScanCameraStatus: Equatable {
  enum Mode: Equatable { case initializing, framing, selecting, capturing, finishing }
  enum Action: Equatable { case findPerson, startCapture, nextPass, buildAvatar }

  var mode: Mode
  var completedPasses = 0
  var shots = 0
  var passComplete = false
  var trackingNormal = true
  var issue: String?
  var selectionHint: String?
  var pendingAction: Action?

  var step: BodyScanStep {
    switch mode {
    case .initializing, .framing, .selecting: .frame
    case .finishing: .build
    case .capturing: completedPasses == 0 ? .body : .detail
    }
  }

  var title: String {
    switch mode {
    case .initializing: return "Opening your camera"
    case .framing: return "Get the whole person in view"
    case .selecting: return "Frame from head to toe"
    case .finishing: return "Saving your capture"
    case .capturing:
      if passComplete && completedPasses == 1 { return "Body circle complete" }
      if passComplete && completedPasses >= 2 && shots >= 60 { return "Your capture is ready" }
      return completedPasses == 0 ? "Walk a slow circle" : "Capture the face and details"
    }
  }

  var instruction: String {
    if let issue { return issue }
    if let selectionHint { return selectionHint }
    switch mode {
    case .initializing: return "Hold the iPhone steady while the camera gets ready."
    case .framing: return "Show the floor around their feet. Move the iPhone slowly to find the space."
    case .selecting: return "Fit the box from head to feet, with their hands inside."
    case .finishing: return "Your photos are being saved before we build the avatar. Keep On You open."
    case .capturing:
      if passComplete && completedPasses == 1 { return "Great. Raise the iPhone near eye level for the detail circle. Keep the same pose."
      }
      if completedPasses >= 2 && shots < 60 { return "We need a little more detail. Continue around the person with their whole body in view." }
      if passComplete && completedPasses >= 2 { return "You can build your avatar now. There’s no need to keep circling." }
      return completedPasses == 0
        ? "Keep the person still. Follow the ring around them at chest height."
        : "Circle slowly near eye level. Keep the whole person in view."
    }
  }

  var action: Action? {
    switch mode {
    case .framing: return .findPerson
    case .selecting: return .startCapture
    case .initializing, .finishing: return nil
    case .capturing:
      if passComplete && (completedPasses < 2 || shots < 60) { return .nextPass }
      if completedPasses >= 2 && shots >= 60 { return .buildAvatar }
      return nil
    }
  }

  var actionTitle: String {
    switch action {
    case .findPerson: "Find person"
    case .startCapture: "Start scanning"
    case .nextPass: completedPasses < 2 ? "Continue to details" : "Capture more detail"
    case .buildAvatar: "Build my avatar"
    case nil: ""
    }
  }

  var pendingTitle: String {
    switch pendingAction {
    case .findPerson: "Finding person…"
    case .startCapture: "Starting capture…"
    case .nextPass: "Starting next circle…"
    case .buildAvatar: "Saving capture…"
    case nil: ""
    }
  }

  var actionEnabled: Bool { pendingAction == nil && trackingNormal && issue == nil }
  var photoProgress: Double { min(1, max(0, Double(shots) / 60)) }
}

enum BodyScanStep: Int, CaseIterable, Identifiable {
  case frame, body, detail, build, ready
  var id: Self { self }
  var title: String {
    switch self {
    case .frame: "Frame"
    case .body: "Body"
    case .detail: "Detail"
    case .build: "Build"
    case .ready: "Ready"
    }
  }
}
