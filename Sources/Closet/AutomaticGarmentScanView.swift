import AVFoundation
import SwiftUI

struct AutomaticGarmentScanView: View {
  var onCapture: (GarmentCaptureResult) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  @State private var capturing = false
  @State private var guidance = "Lay a short-sleeved shirt flat, with the collar at the top. Hold the phone directly above it."

  var body: some View {
    Group {
      if capturing {
        GarmentCaptureCamera(onResult: { result in onCapture(result); dismiss() }, onGuidance: { guidance = $0 })
          .overlay(alignment: .center) {
            RoundedRectangle(cornerRadius: 24)
              .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
              .padding(28)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
          .safeAreaInset(edge: .bottom) {
            Text(guidance)
              .font(.callout).multilineTextAlignment(.center)
              .padding().frame(maxWidth: .infinity)
              .background(.regularMaterial)
              .accessibilityIdentifier("garment.guidance")
          }
      } else {
        List {
          Section {
            Label("Lay it flat. We’ll do the rest.", systemImage: "tshirt").font(.headline)
            Text("Use a short-sleeved shirt on a plain surface that contrasts with the fabric. Smooth out folds and spread the sleeves.")
          }
          Section {
            Label("Collar toward the top", systemImage: "tshirt")
            Label("Hold directly overhead", systemImage: "camera")
            Label("Keep every edge visible", systemImage: "camera.viewfinder")
          } footer: {
            Text("Capture happens automatically once shape and depth are clear and consistent. No points to tap. No measurements to enter.")
          }
          Section {
            if GarmentCaptureController.supported {
              Button("Continue to camera") { capturing = true }
                .accessibilityIdentifier("garment.start")
            } else {
              Text("Depth capture unavailable")
                .font(.headline)
              Text("Open On You on a LiDAR iPhone for automatic dimensions. On this device, add a garment photo to your closet instead.")
                .foregroundStyle(.secondary)
            }
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
              Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
              }
            }
          }
        }
      }
    }
    .navigationTitle("Scan a shirt")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { capturing = false; guidance = GarmentCaptureError.interrupted.localizedDescription }
    }
  }
}
