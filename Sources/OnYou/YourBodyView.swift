import SwiftUI

struct YourBodyView: View {
  var store: OnYouStore
  var scans: AvatarScanStore
  @State private var showingCapture = false
  @State private var confirmingDelete = false
  @AppStorage("on-you.wireframe") private var wireframe = false

  var body: some View {
    VStack(spacing: 0) {
      if let asset = scans.asset {
        ScannedAvatarPreview(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        VStack(spacing: 6) {
          Text("Your scan").font(.headline)
          Text("Drag to rotate. Pinch to look closer.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
      } else if scans.hasUnreadableScan {
        ContentUnavailableView("Scan unavailable", systemImage: "camera", description: Text("Your saved scan couldn’t be loaded. Start a new scan to replace it."))
      } else {
        BodySceneView(measurements: store.current ?? .example, wireframe: wireframe)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        VStack(spacing: 6) {
          Text(store.current == nil ? "Example body" : "Your body").font(.headline)
          Text(store.current == nil ? "Create your avatar with a body scan." : "From your measurements")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
      }
      HStack(spacing: 12) {
        Button(scans.asset == nil ? "Scan your body" : "New scan", systemImage: "camera") { showingCapture = true }
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
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
    .fullScreenCover(isPresented: $showingCapture) {
      BodyScanFlowView(store: scans)
    }
    .confirmationDialog("Delete your saved scan?", isPresented: $confirmingDelete, titleVisibility: .visible) {
      Button("Delete scan", role: .destructive) { scans.delete() }
    } message: {
      Text("This removes the captured avatar from this iPhone. Your closet is kept.")
    }
  }
}
