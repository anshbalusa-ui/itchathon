import AVFoundation
import RealityKit
import SwiftUI

struct BodyScanFlowView: View {
  var store: AvatarScanStore
  var initialHeight: Double?
  var onSaved: () -> Void
  @State private var model = BodyCaptureModel()
  @State private var height = ""
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL

  var body: some View {
    NavigationStack {
      Group {
        switch model.phase {
        case .setup: setup
        case .preparing: ProgressView("Starting camera…").frame(maxWidth: .infinity, maxHeight: .infinity)
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
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { model.cancel(); dismiss() }
        }
      }
    }
    .interactiveDismissDisabled(model.phase != .setup)
    .onAppear { if let initialHeight { height = initialHeight.formatted(.number.grouping(.never)) } }
    .onChange(of: scenePhase) { _, phase in if phase == .background { model.suspend() } }
    .onDisappear { model.cancel() }
  }

  private var title: String {
    switch model.phase {
    case .review: "Review scan"
    case .reconstructing: "Building avatar"
    default: "Scan your body"
    }
  }

  private var setup: some View {
    Form {
      Section {
        Label("A helper holds the iPhone", systemImage: "camera")
          .font(.headline)
        Text("Stand still while they walk around you. Keep your arms slightly away from your body and your feet apart.")
      }
      Section("Before you start") {
        Text("Use bright, even light. Avoid mirrors, direct sunlight, and loose clothing. Tie long hair away from your face.")
        Text("Frame your whole body, including your feet. Complete one full circle at chest height, then another at head height. Keep the same pose and expression.")
      }
      Section {
        HStack {
          Text("Measured height")
          TextField("Required", text: $height)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("Measured height in centimeters")
            .accessibilityIdentifier("scan.height")
          Text("cm").foregroundStyle(.secondary)
        }
      } header: {
        Text("Height reference")
      } footer: {
        Text("Measure barefoot. This sets the model’s scale. A captured height more than 10% away from this reference requires a retake.")
      }
      Section {
        if BodyCaptureModel.isSupported {
          Button("Continue to camera") {
            guard let value = parsedHeight else { return }
            model.referenceHeightCM = value
            Task { await model.start() }
          }
          .disabled(parsedHeight == nil)
          .accessibilityIdentifier("scan.start")
        } else {
          Label("LiDAR capture unavailable", systemImage: "camera")
          Text("Open On You on a supported LiDAR iPhone to capture a 3D body. The simulator can display models but has no LiDAR.")
            .foregroundStyle(.secondary)
        }
      } footer: {
        Text("The scan captures visible skin, face, hair, and clothing. Movement can distort geometry; clothing hides the body beneath it. Photos are processed on this iPhone and removed after reconstruction.")
      }
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var parsedHeight: Double? {
    let raw = height.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
    guard let value = Double(raw), BodyMeasurementField.height.range.contains(value) else { return nil }
    return value
  }

  private func captureView(_ session: ObjectCaptureSession) -> some View {
    ObjectCaptureView(session: session)
      .overlay(alignment: .top) {
        Text(guidance(session))
          .font(.callout.weight(.medium))
          .multilineTextAlignment(.center)
          .padding(12)
          .frame(maxWidth: .infinity)
          .background(.regularMaterial)
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 12) {
          if session.state == .capturing {
            HStack {
              Text("\(session.numberOfShotsTaken) images")
              Spacer()
              Text("\(min(2, model.completedPasses)) of 2 passes")
            }
            .font(.subheadline).monospacedDigit()
          }
          switch session.state {
          case .ready:
            Button("Select body") { _ = session.startDetecting() }
              .buttonStyle(.borderedProminent)
          case .detecting:
            Text("Fit the selection box closely around the person, from head to feet.")
              .font(.footnote).foregroundStyle(.secondary)
            Button("Start capture") { session.startCapturing() }
              .buttonStyle(.borderedProminent)
          case .capturing:
            if session.userCompletedScanPass && (model.completedPasses < 2 || session.numberOfShotsTaken < 60) {
              Button(model.completedPasses < 2 ? "Start head-height pass" : "Capture more views") { model.nextPass() }
                .buttonStyle(.borderedProminent)
            } else {
              Button("Build avatar") { model.finish() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canFinish)
            }
          default: ProgressView("Preparing capture…")
          }
        }
        .controlSize(.large)
        .padding(16)
        .background(.regularMaterial)
      }
      .onChange(of: session.state) { _, state in
        if model.capture === session { model.stateChanged(state) }
      }
      .onChange(of: session.userCompletedScanPass) { _, complete in
        if model.capture === session { model.passCompleted(complete) }
      }
  }

  private func guidance(_ session: ObjectCaptureSession) -> String {
    let feedback = session.feedback
    if feedback.contains(.environmentTooDark) || feedback.contains(.environmentLowLight) { return "Move to brighter, even lighting." }
    if feedback.contains(.movingTooFast) { return "Move the iPhone more slowly. Keep the person still." }
    if feedback.contains(.outOfFieldOfView) { return "Keep the whole person in the frame." }
    if feedback.contains(.objectTooClose) { return "Step back to include the whole body." }
    if feedback.contains(.objectTooFar) { return "Move closer while keeping head and feet visible." }
    if session.cameraTracking != .normal { return "Move slowly while camera tracking settles." }
    if model.completedPasses >= 2 && session.numberOfShotsTaken < 60 { return "Capture at least 60 images. Continue slowly around the person." }
    return model.completedPasses == 0 ? "Walk slowly around the person at chest height." : "Complete another circle at head height. Keep the face in focus."
  }

  private var reconstruction: some View {
    VStack(spacing: 20) {
      ProgressView(value: model.progress) { Text(model.stage) }
      Text("Building the captured surface and photo texture. Keep On You open.")
        .foregroundStyle(.secondary)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var review: some View {
    List {
      if let url = model.modelURL, let calibration = model.calibration {
        Section {
          ScannedAvatarPreview(url: url, referenceHeightCM: model.referenceHeightCM)
            .frame(height: 380)
            .listRowInsets(EdgeInsets())
        }
        Section("Scale check") {
          LabeledContent("Reference height", value: "\(model.referenceHeightCM.formatted()) cm")
          LabeledContent("Captured height", value: "\((calibration.size.y * 100).formatted(.number.precision(.fractionLength(1)))) cm")
          LabeledContent("Scale adjustment", value: "\((abs(calibration.scale - 1) * 100).formatted(.number.precision(.fractionLength(1))))%")
          LabeledContent("Captured images", value: model.imageCount.formatted())
        }
        Section {
          Text("Drag to inspect every side, especially the face, hands, and gaps around the arms. Retake if anything is stretched, missing, or merged with the room.")
          Text("Height is calibrated to your reference. Other dimensions are unverified until compared with a tape measure.")
            .foregroundStyle(.secondary)
          Button("Use this avatar") {
            if model.save(to: store) { dismiss(); onSaved() }
          }
          Button("Retake scan", role: .destructive) { model.cancel() }
        }
      }
    }
  }

  private func failure(_ message: String) -> some View {
    ContentUnavailableView {
      Label("Scan couldn’t finish", systemImage: "camera")
    } description: {
      Text(message)
    } actions: {
      if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
      }
      Button("Try again") { model.cancel() }
    }
  }
}
