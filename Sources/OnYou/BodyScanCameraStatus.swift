import Foundation

struct BodyScanCameraStatus: Equatable {
  enum Mode: Equatable { case initializing, framing, selecting, capturing, finishing }
  enum Action: Equatable { case findPerson, startCapture, nextPass, buildAvatar, retakeScan }

  var mode: Mode
  var completedPasses = 0
  var shots = 0
  var passComplete = false
  var trackingNormal = true
  var issue: String?
  var selectionHint: String?
  var pendingAction: Action?
  var maximumShots: Int?

  var exhaustedCaptureCapacity: Bool {
    guard let maximumShots, maximumShots > 0 else { return false }
    return mode == .capturing && shots >= maximumShots
      && !AvatarScanInput.hasCoverage(images: shots, passes: completedPasses)
  }

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
      if exhaustedCaptureCapacity { return "This scan needs another try" }
      if passComplete && completedPasses == 1 { return "Body circle complete" }
      if AvatarScanInput.hasCoverage(images: shots, passes: completedPasses) { return "Your capture is ready" }
      if passComplete && completedPasses >= 2 { return "Detail circle complete" }
      return completedPasses == 0 ? "Walk a slow circle" : "Capture the face and details"
    }
  }

  var instruction: String {
    if exhaustedCaptureCapacity {
      return "Stop walking. The camera reached its photo limit before coverage was complete. Retake the scan, following each ring. Your saved avatar is unchanged."
    }
    if awaitsNextStep {
      if completedPasses < 2 {
        return "Stop walking. Capture is paused. Raise the iPhone near eye level, then tap Continue to details. Hold the same pose."
      }
      if shots < 60 {
        return "Stop walking. This circle is complete, but we need more photos before building. Tap Capture more detail to start a fresh ring."
      }
      return "Stop walking. Capture is paused. Tap Build my avatar, then relax your pose."
    }
    if let issue, mode != .finishing { return issue }
    if let selectionHint { return selectionHint }
    switch mode {
    case .initializing: return "Hold the iPhone steady while the camera gets ready."
    case .framing: return "Show the floor around their feet. Move the iPhone slowly to find the space."
    case .selecting: return "Fit the box from head to feet, with their hands inside."
    case .finishing: return "Your photos are being saved before we build the avatar. Keep On You open."
    case .capturing:
      if completedPasses >= 2 && shots < 60 { return "We need a little more detail. Continue around the person with their whole body in view." }
      return completedPasses == 0
        ? "Keep the person still. Follow the ring at chest height. We’ll pause when the circle is complete."
        : "Circle slowly near eye level. Keep the whole person in view. We’ll pause when the detail ring is complete."
    }
  }

  var action: Action? {
    switch mode {
    case .framing: return .findPerson
    case .selecting: return .startCapture
    case .initializing, .finishing: return nil
    case .capturing:
      if exhaustedCaptureCapacity { return .retakeScan }
      if passComplete && (completedPasses < 2 || shots < 60) { return .nextPass }
      if AvatarScanInput.hasCoverage(images: shots, passes: completedPasses) { return .buildAvatar }
      return nil
    }
  }

  var actionTitle: String {
    switch action {
    case .findPerson: "Find person"
    case .startCapture: "Start scanning"
    case .nextPass: completedPasses < 2 ? "Continue to details" : "Capture more detail"
    case .buildAvatar: "Build my avatar"
    case .retakeScan: "Retake scan"
    case nil: ""
    }
  }

  var pendingTitle: String {
    switch pendingAction {
    case .findPerson: "Finding person…"
    case .startCapture: "Starting capture…"
    case .nextPass: "Starting next circle…"
    case .buildAvatar: "Saving capture…"
    case .retakeScan: "Starting over…"
    case nil: ""
    }
  }

  var awaitsNextStep: Bool {
    mode == .capturing && (passComplete || exhaustedCaptureCapacity || AvatarScanInput.hasCoverage(images: shots, passes: completedPasses))
  }

  var actionEnabled: Bool {
    guard pendingAction == nil else { return false }
    // Completed capture transitions use saved evidence, not live framing feedback.
    if action == .nextPass || action == .buildAvatar || action == .retakeScan { return true }
    return trackingNormal && issue == nil
  }

  var progressTitle: String {
    if completedPasses >= 2 && shots >= 60 { return "Capture complete" }
    if awaitsNextStep { return completedPasses < 2 ? "Body complete · Details next" : "More photo detail needed" }
    return completedPasses == 0 ? "Body circle in progress" : "Detail circle in progress"
  }

  var progressDetail: String {
    if awaitsNextStep { return "Capture paused · Continue below" }
    if completedPasses == 0 { return "Fill the camera ring. The detail circle comes next." }
    return shots >= 60 ? "Enough photos. Finish the detail ring to continue." : "Fill the detail ring. Photos are captured automatically."
  }
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
