import AVFoundation
import SwiftUI

struct BodyScanFlowView: View {
  var store: AvatarScanStore
  @State private var model = BodyCaptureModel()
  @State private var confirmingDiscard = false
  @State private var confirmingRetake = false
  @State private var previousIdleTimerSetting: Bool?
  @State private var started = false
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      Group {
        if !BodyCaptureModel.isSupported {
          unavailable
        } else {
          switch model.phase {
          case .setup, .preparing: preparing
          case .capturing:
            if let directory = model.captureDirectory { captureView(directory) }
          case .reconstructing: reconstruction
          case .review: review
          case .failed(let message): failure(message)
          }
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.phase != .capturing {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close scan", systemImage: "xmark", action: requestClose)
              .labelStyle(.iconOnly)
              .accessibilityIdentifier("scan.close")
          }
        }
      }
    }
    .interactiveDismissDisabled()
    .task {
      guard !started else { return }
      started = true
      await model.start()
    }
    .onChange(of: scenePhase) { _, phase in if phase == .background { model.suspend() } }
    .onAppear {
      previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
      updateIdleTimer()
    }
    .onChange(of: model.phase) { _, phase in
      updateIdleTimer()
      if phase == .review {
        AccessibilityNotification.Announcement("Ready to review. Hand the phone back.").post()
      } else if phase == .reconstructing {
        AccessibilityNotification.Announcement("Checking your scan.").post()
      }
    }
    .sensoryFeedback(.success, trigger: model.phase) { old, new in haptics && old != .review && new == .review }
    .onDisappear {
      model.cancel()
      if let previousIdleTimerSetting { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting }
      previousIdleTimerSetting = nil
    }
    .alert("Discard this scan?", isPresented: $confirmingDiscard) {
      Button("Discard scan", role: .destructive) { model.cancel(); dismiss() }
      Button("Keep scanning", role: .cancel) {}
    } message: {
      Text("This capture will be removed. Your saved avatar will stay as it is.")
    }
    .confirmationDialog("Retake this scan?", isPresented: $confirmingRetake, titleVisibility: .visible) {
      Button("Retake", role: .destructive, action: restartCapture)
    } message: {
      Text("This capture will be removed. Your saved avatar stays as it is.")
    }
    .alert("Avatar couldn’t be saved", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.clearSaveError() } })) {
      Button("OK", role: .cancel) { model.clearSaveError() }
    } message: { Text(model.saveError ?? "") }
  }

  private var title: String {
    switch model.phase {
    case .review: "Review scan"
    default: "Scan body"
    }
  }

  private var unavailable: some View {
    ContentUnavailableView {
      Label("Body scan unavailable", systemImage: "camera")
    } description: {
      Text("Body capture needs a supported LiDAR iPhone.")
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("scan.unsupported")
  }

  private var preparing: some View {
    VStack(spacing: 24) {
      Spacer()
      ProgressView().controlSize(.large)
      Text("Getting the camera ready").font(.title2.weight(.semibold))
      Text("Ask a helper to hold iPhone and keep the space around you clear.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center)
      Spacer()
    }
    .padding(24)
  }

  private func captureView(_ directory: URL) -> some View {
    let captureID = model.captureID
    return BodyScanCameraView(status: model.cameraStatus, position: model.position,
                             close: requestClose, performAction: model.performCameraAction,
                             paused: confirmingDiscard, pauseCapture: model.setCapturePromptVisible) {
      BodyCaptureCamera(directory: directory, seed: model.captureSeed, missingAngles: model.requestedAngles,
        onReady: { model.cameraReady($0, directory: directory, captureID: captureID) },
        onUpdate: { model.cameraUpdated($0, directory: directory, captureID: captureID) },
        onFinished: { model.cameraFinished($0, directory: directory, captureID: captureID) },
        onFailure: { model.cameraFailed($0, directory: directory, captureID: captureID) })
      .id(captureID)
    }
  }

  private var reconstruction: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Checking your scan…")
          .font(.title2.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        if model.hasBuildProgress {
          ProgressView(value: model.progress) {
            Text(model.stage).accessibilityIdentifier("scan.build.stage")
          } currentValueLabel: {
            Text(BodyScanTiming.remaining(model.estimatedRemainingTime))
              .accessibilityIdentifier("scan.build.time")
          }
          .accessibilityIdentifier("scan.build.progress")
        } else {
          ProgressView(model.stage)
            .accessibilityIdentifier("scan.build.stage")
        }
        Text("Keep On You open while we check the scan.")
          .font(.callout).foregroundStyle(.secondary)
      }
      .frame(maxWidth: 440, alignment: .leading)
      .padding(24)
      .frame(maxWidth: .infinity)
    }
    .defaultScrollAnchor(.center, for: .alignment)
    .scrollBounceBehavior(.basedOnSize)
  }

  @ViewBuilder private var review: some View {
    if let url = model.modelURL, let calibration = model.calibration {
      BodyScanReviewView(url: url, referenceHeightCM: calibration.referenceHeightCM,
                         preparedScene: model.preparedScene, retake: requestRetake) {
        if model.save(to: store) { dismiss() }
      }
    }
  }

  private func failure(_ message: String) -> some View {
    let needsViews: Bool
    if case .missingViews = model.recovery { needsViews = true } else { needsViews = false }
    return ContentUnavailableView {
      Label(needsViews ? "More views needed" : "Scan couldn’t continue", systemImage: "camera")
    } description: {
      if let angle = model.requestedAngles.first, let direction = model.captureSeed?.direction {
        Text("\(BodyCaptureView.nearest(to: angle, direction: direction).title) needed. Other views are kept.")
      } else {
        Text(message)
      }
    } actions: {
      switch model.recovery {
      case .missingViews:
        Button("Capture missing views", action: model.captureMissingViews)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("scan.recovery.capture")
      case .retryProcessing:
        Button("Retry processing", action: model.retryProcessing)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("scan.recovery.retry")
        Button("Retake", action: requestRetake)
      case .retake, nil:
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied,
           let settings = URL(string: UIApplication.openSettingsURLString) {
          Link("Open Settings", destination: settings).buttonStyle(.borderedProminent)
          Button("Retake", action: requestRetake)
        } else {
          Button("Retake", action: requestRetake).buttonStyle(.borderedProminent)
        }
      }
    }
  }

  private func requestClose() {
    if model.hasUnsavedCapture {
      confirmingDiscard = true
    } else {
      model.cancel()
      dismiss()
    }
  }

  private func requestRetake() {
    if model.hasUnsavedCapture { confirmingRetake = true }
    else { restartCapture() }
  }

  private func restartCapture() {
    Task { await model.start() }
  }

  private func updateIdleTimer() {
    guard let previousIdleTimerSetting else { return }
    let working = model.phase == .preparing || model.phase == .capturing || model.phase == .reconstructing
    UIApplication.shared.isIdleTimerDisabled = working || previousIdleTimerSetting
  }
}
