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
  var fullBodyViews = 0
  enum Feedback: Hashable {
    case environmentTooDark, environmentLowLight, movingTooFast
    case outOfFieldOfView, objectTooClose, objectTooFar, objectNotDetected
  }

  enum Guidance: Equatable {
    case lighting, movement, tooClose, tooFar, paused, selection, tracking, framing
    var message: String {
      switch self {
      case .lighting: "Add more light."
      case .movement: "Move more slowly."
      case .tooClose: "Step back to include their feet."
      case .tooFar: "Move a little closer."
      case .paused: "Scan paused."
      case .selection: "Drag the corners to include head and feet."
      case .tracking: "Move the iPhone slowly."
      case .framing: "Keep head and feet in view."
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


  var hasFullBodyEvidence: Bool { fullBodyViews >= 3 }
  var captureReady: Bool { AvatarScanInput.hasCoverage(images: shots, passes: completedPasses) && hasFullBodyEvidence }

  var currentPass: Int { completedPasses >= 2 ? 2 : max(1, completedPasses + (passComplete ? 0 : 1)) }
  var passLabel: String { currentPass == 1 ? "Body circle" : "Detail circle" }


  var exhaustedCaptureCapacity: Bool {
    guard let maximumShots, maximumShots > 0 else { return false }
    return mode == .capturing && shots >= maximumShots
      && !captureReady
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
    case .framing: return "Find the floor"
    case .selecting: return "Frame from head to toe"
    case .finishing: return "Saving your capture"
    case .capturing:
      if exhaustedCaptureCapacity { return "This scan needs another try" }
      if passComplete && completedPasses == 1 { return "Body circle complete" }
      if captureReady { return "Your capture is ready" }
      if passComplete && completedPasses >= 2 { return hasFullBodyEvidence ? "Detail circle complete" : "Include the whole body" }
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
      if !hasFullBodyEvidence { return "Head and feet aren’t clear yet. Keep the whole person visible for another circle." }
      return "Stop walking. Tap Build my avatar, then relax your pose."
    }
    if let selectionHint { return selectionHint }
    if let issue, mode != .finishing { return issue }
    switch mode {
    case .initializing: return "Hold the iPhone steady while the camera gets ready."
    case .framing: return "Point at the floor beside their feet."
    case .selecting: return "Drag the corners to include head and feet."
    case .finishing: return "Your photos are being saved before we build the avatar. Keep On You open."
    case .capturing:
      if shots >= 6 && !hasFullBodyEvidence { return "Keep head and feet in view." }
      if completedPasses >= 2 && shots < 60 { return "We need a little more detail. Continue around the person with their whole body in view." }
      return completedPasses == 0
        ? "Walk slowly around the person. Follow the ring."
        : "Keep the same pose. Follow the second ring."
    }
  }

  var action: Action? {
    switch mode {
    case .framing: return .findPerson
    case .selecting: return .startCapture
    case .initializing, .finishing: return nil
    case .capturing:
      if exhaustedCaptureCapacity { return .retakeScan }
      if passComplete && (completedPasses < 2 || shots < 60 || !hasFullBodyEvidence) { return .nextPass }
      if captureReady { return .buildAvatar }
      return nil
    }
  }

  var actionTitle: String {
    switch action {
    case .findPerson: "Set floor"
    case .startCapture: "Start scan"
    case .nextPass: completedPasses < 2 ? "Continue to details" : "Capture more detail"
    case .buildAvatar: "Build my avatar"
    case .retakeScan: "Retake scan"
    case nil: ""
    }
  }

  var pendingTitle: String {
    switch pendingAction {
    case .findPerson: "Finding floor…"
    case .startCapture: "Starting capture…"
    case .nextPass: "Starting next circle…"
    case .buildAvatar: "Saving capture…"
    case .retakeScan: "Starting over…"
    case nil: ""
    }
  }

  var awaitsNextStep: Bool {
    mode == .capturing && (passComplete || exhaustedCaptureCapacity || captureReady)
  }

  var actionEnabled: Bool {
    // SDK state admits commands; advisory feedback must never deadlock the Start button.
    pendingAction == nil && action != nil
  }

  var progressTitle: String {
    if captureReady { return "Capture complete" }
    if awaitsNextStep { return completedPasses < 2 ? "Body complete · Details next" : "More photo detail needed" }
    if completedPasses >= 2 { return "\(shots) photos · Extra detail" }
    return "\(shots) photos · Circle \(currentPass) of 2"
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
