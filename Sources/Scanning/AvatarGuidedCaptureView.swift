#if DEBUG
import SwiftUI
import UIKit

struct AvatarGuidedCaptureView: UIViewControllerRepresentable {
    @ObservedObject var model: AvatarScannerModel

    final class Coordinator {
        let model: AvatarScannerModel
        init(model: AvatarScannerModel) { self.model = model }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AvatarGuidedCaptureController {
        let controller = AvatarGuidedCaptureController()
        model.attach(controller)
        controller.onReady = { [weak model, weak controller] in
            guard let model, let controller, model.isAttached(to: controller) else { return }
            model.start()
        }
        controller.onDisappear = { [weak model, weak controller] in
            guard let model, let controller, model.isAttached(to: controller) else { return }
            model.cancel()
        }
        return controller
    }

    func updateUIViewController(_ controller: AvatarGuidedCaptureController, context: Context) {}

    static func dismantleUIViewController(_ controller: AvatarGuidedCaptureController, coordinator: Coordinator) {
        coordinator.model.detach(controller)
        controller.shutdown()
    }
}

/// Consent/capability introduction, reachable only through the internal pilot.
struct CreateAvatarView: View {
    @State private var showScanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Label("Development scanner", systemImage: "camera.viewfinder")
                    .font(.title2.bold())
                Text("Stand where your full body is visible.")
                    .font(.title.weight(.semibold))
                Text("Use the rear camera on a LiDAR-equipped iPhone Pro. A helper or a stable phone mount may be needed. Keep the phone upright.")
                Text("The camera will look for a steady front view, then ask you to turn sideways. Inconclusive views will not be accepted.")
                Label("Camera data stays in memory", systemImage: "lock.shield")
                    .font(.headline)
                Text("This development capture does not save or upload photos, depth maps, or person masks. Cancel or leave the scanner to discard its observations.")
                    .foregroundStyle(.secondary)
                Text("The scanner and its view checks still require physical-device validation. It does not create an avatar or establish body accuracy or garment fit.")
                    .foregroundStyle(.secondary)
                Button("Start guided scan", systemImage: "camera") { showScanner = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("start-guided-scan")
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Guided capture")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showScanner) { AvatarScannerScreen() }
    }
}

private struct AvatarScannerScreen: View {
    @StateObject private var model = AvatarScannerModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AvatarGuidedCaptureView(model: model)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if scenePhase != .active {
                // Cover the preview before the OS takes a background snapshot.
                Color.black.ignoresSafeArea()
            }
            VStack(spacing: 24) {
                HStack {
                    Text("Development capture").font(.caption.bold())
                    Spacer()
                    Button("Cancel scan", systemImage: "xmark") {
                        model.cancel()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(.regularMaterial)
                Spacer(minLength: 0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        instructions
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .fixedSize(horizontal: false, vertical: true)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
        }
        .accessibilityIdentifier("guided-scanner")
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.suspend() }
        }
        .onDisappear { model.cancel() }
    }

    @ViewBuilder private var instructions: some View {
        switch model.phase {
        case .idle:
            ProgressView("Getting the camera ready")
        case .requestingPermission:
            ProgressView("Waiting for camera permission")
        case let .scanning(view):
            Text(view == .front ? "Stand facing the camera" : "Turn sideways")
                .font(.title2.bold())
            Text(guidance(for: model.guidance, view: view))
                .foregroundStyle(.secondary)
        case let .unavailable(reason):
            Text("Camera unavailable").font(.title2.bold())
            if reason == .unsupportedDevice {
                Text("This guided capture needs a LiDAR-equipped iPhone Pro. It cannot run in the simulator or on an unsupported device.")
            } else if reason == .cameraRestricted {
                Text("Camera access is restricted on this iPhone. No capture has started.")
            } else {
                Text("Allow camera access in Settings, then try again. No capture has started.")
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                retryButton
            }
        case let .retryRequired(reason):
            Text("Let's try again").font(.title2.bold())
            Text(reason == .orientationChanged
                 ? "Hold the iPhone upright, then start again."
                 : "The camera view was interrupted or inconclusive. Keep the same person fully visible and start again.")
            retryButton
        case .candidatePairReady:
            Text("Views captured for review").font(.title2.bold())
            Text("These camera observations are provisional, not a validated body scan. Avatar creation is not available, and nothing has been saved.")
            Button("Discard and try again") { model.start() }
            Button("Done") { model.cancel(); dismiss() }
                .buttonStyle(.borderedProminent)
        case .cancelled:
            Text("Capture stopped").font(.title2.bold())
            Text("The temporary observations have been discarded.")
            retryButton
        }
    }

    private var retryButton: some View {
        Button("Try again", systemImage: "arrow.clockwise") { model.start() }
            .buttonStyle(.borderedProminent)
    }

    private func guidance(for rejection: ScanRejection?, view: ScanCaptureView) -> String {
        switch rejection {
        case .missingPerson, .incompleteFraming:
            return "Move back a little so your full body is visible."
        case .multiplePeople:
            return "Keep only the person being scanned in view."
        case .trackingLimited, .holdStill:
            return "Hold still and keep the phone steady."
        case .unverifiedView, .wrongView:
            return view == .front ? "Face the camera with your full body visible."
                : "Turn a little and hold still. We need a clear sideways view."
        case .unavailableDepth, .insufficientPersonDepth, .invalidAlignment, .unreliablePose:
            return "We can't get a clear view. Keep your full body visible and try better lighting."
        case .unsupportedOrientation:
            return "Hold the iPhone upright."
        case .staleFrame:
            return "The camera is catching up. Hold still."
        case nil:
            return "Keep your full body visible and hold still."
        }
    }
}
#endif
