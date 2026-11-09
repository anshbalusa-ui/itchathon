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
  enum Feedback: Hashable {
    case environmentTooDark, environmentLowLight, movingTooFast
    case outOfFieldOfView, objectTooClose, objectTooFar, objectNotDetected
  }

  enum Guidance: Equatable {
    case lighting, movement, tooClose, tooFar, paused, selection, tracking, framing
    var message: String {
      switch self {
      case .lighting: "Find brighter, even light so we can see the person clearly."
      case .movement: "Slow down. Keep the iPhone steady and the person still."
      case .tooClose: "Move back a little. Keep their head and feet visible."
      case .tooFar: "Move a little closer without cutting off their head or feet."
      case .paused: "Capture is paused. Keep On You in the foreground to continue."
      case .selection: "Keep the person centered inside the selection box."
      case .tracking: "Slowly move the iPhone so it can find the floor and settle its tracking."
      case .framing: "Bring the whole person back into view, with their head and feet visible."
      }
    }
  }

  static func guidance(for feedback: Set<Feedback>, mode: Mode, capturePaused: Bool,
                       trackingNormal: Bool) -> Guidance? {
    if feedback.contains(.environmentTooDark) || feedback.contains(.environmentLowLight) { return .lighting }
    if feedback.contains(.movingTooFast) { return .movement }
    if feedback.contains(.objectTooClose) { return .tooClose }
    if feedback.contains(.objectTooFar) { return .tooFar }
    if capturePaused { return .paused }
    if feedback.contains(.objectNotDetected) && mode != .framing { return .selection }
    if !trackingNormal { return .tracking }
    if feedback.contains(.outOfFieldOfView) { return .framing }
    return nil
  }


  var currentPass: Int { completedPasses >= 2 ? 2 : max(1, completedPasses + (passComplete ? 0 : 1)) }
  var passLabel: String { currentPass == 1 ? "Body circle" : "Detail circle" }


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
        return "Stop walking. Capture is paused. Keep the same pose, then tap Continue to details."
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
        ? "Keep the person still and follow the coverage ring for the body circle. We’ll pause when it’s complete."
        : "Follow the coverage ring for the detail circle. Keep the whole person in view and their pose still. We’ll pause when it’s complete."
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
    return "Pass \(currentPass) of 2 · \(passLabel) in progress"
  }

  var progressDetail: String {
    if awaitsNextStep {
      return completedPasses < 2
        ? "Pass 1 of 2 complete · Capture paused · Continue to details below."
        : shots < 60
          ? "Both circles complete · Capture paused · Continue around the person for more photos."
          : "Both circles complete · Capture paused · Build your avatar below."
    }
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
