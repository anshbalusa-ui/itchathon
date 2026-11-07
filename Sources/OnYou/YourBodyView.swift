import SwiftUI

struct YourBodyView: View {
  var store: OnYouStore
  var scans: AvatarScanStore
  var showScan: () -> Void
  @AppStorage("on-you.wireframe") private var wireframe = false

  var body: some View {
    VStack(spacing: 0) {
      if let asset = scans.asset {
        ScannedAvatarPreview(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        VStack(spacing: 6) {
          Text("Your scan").font(.headline)
          Text("\(asset.record.referenceHeightCM.formatted()) cm · \(asset.record.date.formatted(date: .abbreviated, time: .omitted))")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding()
      } else if scans.hasUnreadableScan {
        ContentUnavailableView("Scan unavailable", systemImage: "camera", description: Text("Your saved scan couldn’t be loaded. Open Scan to retry or start again."))
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
      Button(scans.asset == nil ? "Scan your body" : "New scan", systemImage: "camera", action: showScan)
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.bottom, 20)
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
  }
}
