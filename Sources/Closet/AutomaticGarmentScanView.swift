import AVFoundation
import SwiftUI

struct AutomaticGarmentScanView: View {
  var onCapture: (GarmentCaptureResult) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openURL) private var openURL
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @State private var capturing = false
  @State private var captureID = UUID()
  @State private var position = ScanPositionFeedback()
  @State private var agreeingFrames = 0
  @State private var panelHeight: CGFloat = 260
  @State private var guidance = "Searching: lay a short-sleeved shirt flat, collar at the top, and hold the iPhone directly overhead."

  var body: some View {
    Group {
      if capturing {
        GeometryReader { geometry in
          ZStack {
            GarmentCaptureCamera(onResult: { result in onCapture(result); dismiss() },
                                 onGuidance: { guidance = $0 }, onPosition: { position = $0 },
                                 onProgress: { agreeingFrames = $0 })
              .id(captureID)
              .ignoresSafeArea()
            VStack {
              HStack {
                Button("Close scanner", systemImage: "xmark") { dismiss() }
                  .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
                Spacer()
                Text("Scan a shirt").font(.headline)
                  .padding(.horizontal, 18).padding(.vertical, 12)
                  .glassEffect(in: .capsule)
                Spacer()
                Menu {
                  Toggle("Guidance haptics", isOn: $haptics)
                } label: { Label("Scan options", systemImage: "ellipsis").labelStyle(.iconOnly) }
                .buttonStyle(.glass).buttonBorderShape(.circle)
              }
              Spacer(minLength: 24)
              ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                  ScanPositionIndicator(position: position)
                  Text(guidance).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("garment.guidance")
                  HStack {
                    Text("\(agreeingFrames) of 3 matching views").font(.caption.weight(.medium))
                    Spacer()
                    Button("Restart scan") {
                      position = ScanPositionFeedback(); agreeingFrames = 0; captureID = UUID()
                    }
                    .font(.subheadline).buttonStyle(.bordered)
                    .accessibilityIdentifier("garment.restart")
                  }
                  Text("Keep every edge visible. Brief movement won’t erase matching views.")
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
              }
              .frame(height: min(panelHeight, geometry.size.height * 0.5))
              .scrollBounceBehavior(.basedOnSize)
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
            }
            .padding(16)
          }
        }
        .preferredColorScheme(.dark)

      } else {
        List {
          Section {
            Label("Lay it flat. We’ll do the rest.", systemImage: "tshirt").font(.headline)
            Text("Use a short-sleeved T-shirt or collared shirt on a plain surface that contrasts with the fabric. Smooth out folds and spread the sleeves.")
          }
          Section {
            Label("Collar toward the top", systemImage: "tshirt")
            Label("Hold directly overhead", systemImage: "camera")
            Label("Keep every edge visible", systemImage: "camera.viewfinder")
          } footer: {
            Text("The scanner recognizes the outline and landmarks, checks metric depth and camera angle, then waits for three agreeing views. Review the result before saving; retake any time.")
          }
          Section {
            if GarmentCaptureController.supported {
              Button("Continue to camera") { capturing = true }
                .accessibilityIdentifier("garment.start")
            } else {
              Text("Depth capture unavailable")
                .font(.headline)
              Text("Open On You on a LiDAR iPhone for automatic dimensions. On this device, add garment photos to your closet instead.")
                .foregroundStyle(.secondary)
            }
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
              Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
              }
            }
          }
          Section {
            Text("After capture, check the cutout and dimensions, then choose Save. No capture is saved automatically.")
          }
        }
      }
    }
    .navigationTitle("Scan a shirt")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { if !capturing { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
    .toolbar(capturing ? .hidden : .visible, for: .navigationBar)
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        capturing = false
        guidance = GarmentCaptureError.interrupted.localizedDescription + " Return to the scanner and restart when ready."
      } else {
        guidance = "Searching: camera paused. Continue when ready, then restart the scan."
      }
    }
  }
}
