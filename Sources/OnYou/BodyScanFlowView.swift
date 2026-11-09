import AVFoundation
import RealityKit
import SwiftUI

struct BodyScanFlowView: View {
  var store: AvatarScanStore
  @State private var model = BodyCaptureModel()
  @State private var confirmingDiscard = false
  @State private var confirmingRetake = false
  @State private var previousIdleTimerSetting: Bool?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack {
      Group {
        switch model.phase {
        case .setup: setup
        case .preparing: preparing
        case .capturing:
          if let capture = model.capture { captureView(capture) }
        case .reconstructing: reconstruction
        case .review: review
        case .failed(let message): failure(message)
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.phase != .capturing {
          ToolbarItem(placement: .cancellationAction) {
            Button("Close scan", systemImage: "xmark", action: requestClose)
              .accessibilityIdentifier("scan.close")
          }
        }
      }
      .toolbar(model.phase == .capturing ? .hidden : .visible, for: .navigationBar)
    }
    .interactiveDismissDisabled()
    .onChange(of: scenePhase) { _, phase in if phase == .background { model.suspend() } }
    .onAppear {
      previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
      updateIdleTimer()
    }
    .onChange(of: model.phase) { _, _ in updateIdleTimer() }
    .onDisappear {
      model.cancel()
      if let previousIdleTimerSetting { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting }
      previousIdleTimerSetting = nil
    }
    .onChange(of: confirmingDiscard) { _, visible in model.setCapturePromptVisible(visible) }
    .confirmationDialog("Discard this scan?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
      Button("Discard scan", role: .destructive) { model.cancel(); dismiss() }
      Button("Keep going", role: .cancel) {}
    } message: {
      Text("This capture will be removed. Your saved avatar will stay as it is.")
    }
    .alert("Avatar couldn’t be saved", isPresented: Binding(get: { model.saveError != nil }, set: { if !$0 { model.clearSaveError() } })) {
      Button("OK", role: .cancel) { model.clearSaveError() }
    } message: { Text(model.saveError ?? "") }
  }

  private var title: String {
    switch model.phase {
    case .review: "Your avatar"
    case .reconstructing: "Building your avatar"
    default: "Scan your body"
    }
  }

  private var setup: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        BodyScanJourneyView(step: .frame)
        VStack(alignment: .leading, spacing: 16) {
          Image(systemName: "figure.stand")
            .font(.system(size: 52, weight: .light))
            .foregroundStyle(.tint)
            .frame(width: 104, height: 104)
            .background(.tint.opacity(0.08), in: Circle())
            .accessibilityHidden(true)
          Text("Let’s get you in frame.")
            .font(.largeTitle.bold())
          Text("Ask someone to hold your iPhone while you stand still. We’ll guide them around you.")
            .font(.title3).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 24) {
          preparationTip("Hold your pose", symbol: "figure.stand", detail: "Stand still with arms slightly away from your torso. Keep head and feet in view. Wear close-fitting clothes and find even light.")
          preparationTip("Body, then detail", symbol: "camera", detail: "Follow the coverage ring for two slow circles around the person. Keep their head and feet in view for each circle.")
          preparationTip("No measurements to enter", symbol: "checkmark", detail: "Depth sets the scale automatically. Your photos stay on this iPhone and are removed after your avatar is built.")
        }
        Text("Capture moves at your pace. Once it’s done, we’ll estimate how long the build has left.")
          .font(.footnote).foregroundStyle(.secondary)

      }
      .padding(24)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 10) {
        if !BodyCaptureModel.isSupported {
          Text("Body capture needs a LiDAR iPhone.")
            .font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("scan.unsupported")
        }
        BodyScanPrimaryButton(title: "Open camera", enabled: BodyCaptureModel.isSupported) {
          Task { await model.start() }
        }
        .accessibilityIdentifier("scan.start")
      }
      .padding(.horizontal, 24).padding(.vertical, 16)
      .background(.bar)
    }
    .background(Color(uiColor: .systemBackground))
  }

  private func preparationTip(_ title: String, symbol: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol)
        .font(.title3).foregroundStyle(.tint)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.headline)
        Text(detail).font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var preparing: some View {
    VStack(spacing: 24) {
      BodyScanJourneyView(step: .frame)
      Spacer()
      ProgressView().controlSize(.large)
      Text("Getting the camera ready").font(.title2.weight(.semibold))
      Text("Keep your helper nearby and the space around you clear.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center)
      Spacer()
    }
    .padding(24)
  }

  private func captureView(_ session: ObjectCaptureSession) -> some View {
    BodyScanCameraView(status: model.cameraStatus, startedAt: model.captureStartedAt,
                       close: requestClose, performAction: model.performCameraAction) {
      // Keep Apple's live camera, coverage ring, and capture animations intact.
      ObjectCaptureView(session: session)
    }
    .onChange(of: session.state, initial: true) { _, state in
      if model.capture === session { model.stateChanged(state) }
    }
    .onChange(of: session.userCompletedScanPass, initial: true) { _, _ in
      if model.capture === session { model.captureProgressChanged() }
    }
    .onChange(of: session.numberOfShotsTaken) { _, _ in
      if model.capture === session { model.captureProgressChanged() }
    }
    .onChange(of: model.cameraStatus.awaitsNextStep) { _, waiting in
      if waiting {
        AccessibilityNotification.Announcement("\(model.cameraStatus.title). \(model.cameraStatus.instruction)").post()
      }
    }
    .task(id: model.pendingAction) {
      guard let action = model.pendingAction else { return }
      do {
        try await Task.sleep(for: .seconds(8))
        model.actionTimedOut(action)
      } catch { }
    }
    .sensoryFeedback(.success, trigger: model.completedPasses)
  }

  private var reconstruction: some View {
    VStack(spacing: 24) {
      BodyScanJourneyView(step: .build)
      Spacer(minLength: 12)
      ZStack {
        Circle().stroke(.quaternary, lineWidth: 6)
        if model.hasBuildProgress {
          Circle().trim(from: 0, to: model.progress)
            .stroke(.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
        Image(systemName: "figure.stand")
          .font(.system(size: 76, weight: .light)).foregroundStyle(.tint)
      }
      .frame(width: 180, height: 180)
      .accessibilityHidden(true)
      VStack(spacing: 10) {
        Text(model.stage).font(.title2.weight(.semibold))
          .accessibilityIdentifier("scan.build.stage")
        Text(BodyScanTiming.remaining(model.estimatedRemainingTime))
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("scan.build.time")
      }
      .multilineTextAlignment(.center)
      if model.hasBuildProgress {
        ProgressView(value: model.progress)
          .accessibilityLabel("Avatar build progress")
          .accessibilityIdentifier("scan.build.progress")
      } else {
        ProgressView("Checking your capture…")
      }
      Text("You can relax your pose. Keep On You open while we bring your photos together.")
        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Spacer(minLength: 12)
      Label("Processed on this iPhone", systemImage: "lock")
        .font(.footnote).foregroundStyle(.secondary)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var review: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        BodyScanJourneyView(step: .ready).padding(.horizontal, 24)
        if let url = model.modelURL, let calibration = model.calibration {
          ScannedAvatarPreview(url: url, referenceHeightCM: calibration.referenceHeightCM,preparedScene: model.preparedScene)
            .frame(height: 420)
        }
        VStack(alignment: .leading, spacing: 10) {
          Text("Take a look around.").font(.title2.weight(.semibold))
          Text("Drag to turn your avatar. Check the face, hands, and space around the arms before saving.")
            .foregroundStyle(.secondary)
          Text("Your scan includes the clothes you wore.")
            .font(.footnote).foregroundStyle(.secondary)
        }.padding(.horizontal, 24)
      }
      .padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 12) {
        BodyScanPrimaryButton(title: "Use this avatar") { if model.save(to: store) { dismiss() } }
        Button("Retake scan") { confirmingRetake = true }
      }
      .padding(.horizontal, 24).padding(.vertical, 16)
      .background(.bar)
    }
    .confirmationDialog("Retake your scan?", isPresented: $confirmingRetake, titleVisibility: .visible) {
      Button("Retake scan", role: .destructive) { model.cancel() }
    } message: { Text("This capture will be removed. Your saved avatar stays as it is.") }
  }

  private func failure(_ message: String) -> some View {
    ContentUnavailableView {
      Label("Let’s try that again", systemImage: "camera")
    } description: {
      Text(message)
    } actions: {
      if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
      }
      Button("Try again") { model.cancel() }
        .buttonStyle(.borderedProminent)
    }
  }

  private func requestClose() {
    switch model.phase {
    case .setup, .preparing, .failed: model.cancel(); dismiss()
    default: confirmingDiscard = true
    }
  }

  private func updateIdleTimer() {
    guard let previousIdleTimerSetting else { return }
    let working = model.phase == .preparing || model.phase == .capturing || model.phase == .reconstructing
    UIApplication.shared.isIdleTimerDisabled = working || previousIdleTimerSetting
  }
}
