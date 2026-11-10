import SwiftUI

struct YourBodyView: View {
  var store: OnYouStore
  var scans: AvatarScanStore
  var synthetic = false
  @State private var showingCapture = false
  @State private var showingMeasurements = false
  @State private var confirmingDelete = false
  @AppStorage("on-you.wireframe") private var wireframe = false
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(spacing: 0) {
      preview
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: typeSize.isAccessibilitySize ? 230 : nil)
      if typeSize.isAccessibilitySize {
        ScrollView { controls }
          .accessibilityIdentifier("body.controls")
      } else {
        controls
      }
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
    .sheet(isPresented: $showingMeasurements) {
      NavigationStack {
        BodyMeasurementsView(store: store) { showingMeasurements = false }
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") { showingMeasurements = false }
                .accessibilityIdentifier("measurement.cancel")
            }
          }
      }
    }
    .fullScreenCover(isPresented: $showingCapture) {
      BodyScanFlowView(store: scans)
    }
    .confirmationDialog("Delete your saved scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete scan", role: .destructive) { scans.delete() }
    } message: {
      Text("This removes the captured avatar from this iPhone. Your closet is kept.")
    }
  }

  @ViewBuilder private var preview: some View {
    if let asset = scans.asset {
      ScannedAvatarPreview(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
    } else if scans.hasUnreadableScan {
      ContentUnavailableView("Scan unavailable", systemImage: "camera", description: Text("Your saved scan couldn’t be loaded. Start a new scan to replace it."))
    } else {
      BodySceneView(measurements: store.current ?? .example, wireframe: wireframe)
    }
  }

  private var controls: some View {
    VStack(spacing: 0) {
      if scans.asset != nil {
        VStack(spacing: 6) {
          Text(synthetic ? "Synthetic avatar" : "Your scan").font(.headline)
          Text("Drag to rotate. Pinch to look closer.")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
      } else if !scans.hasUnreadableScan {
        VStack(spacing: 6) {
          Text(store.current == nil ? "Example body" : "Your body").font(.headline)
          Text(store.current == nil ? "Scan your body or enter measurements." : "Measurement illustration · Not a body scan")
            .font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
      }
      if scans.asset == nil && !scans.hasUnreadableScan {
        Button {
          showingMeasurements = true
        } label: {
          Label("Measurements", systemImage: "ruler")
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier("body.measurements")
        .padding(.bottom, 12)
      }
      HStack(spacing: 12) {
        Button { showingCapture = true } label: {
          Label(scans.asset == nil ? "Scan your body" : "New scan", systemImage: "camera")
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("scan.open")
        if scans.asset != nil || scans.hasUnreadableScan {
          Button("Delete scan", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
        }
      }
      .controlSize(.large)
      .padding(.bottom, 20)
    }
  }
}
