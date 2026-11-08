import SwiftUI

struct TryOnView: View {
  var avatar: AvatarScanAsset
  var garment: ClosetGarment
  var photoURL: URL
  @State private var model = TryOnModel()
  @State private var attempt = UUID()
  @State private var showingShirt = true
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if let result = model.result {
          VStack(spacing: 0) {
            BodySceneView(measurements: .example,
                          scan: ScannedBodySource(url: avatar.url, referenceHeightCM: avatar.record.referenceHeightCM),
                          tryOn: result, showingGarment: showingShirt)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .accessibilityIdentifier("tryon.scene")
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(result.shape.needsRoom ? "Less room through the body" : "Room through the body")
                    .font(.headline)
                  Text(result.shape.belowHips ? "Falls below the hips" : "Finishes above the hips")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Shirt", systemImage: "tshirt", isOn: $showingShirt)
                  .toggleStyle(.button).buttonStyle(.bordered)
                  .accessibilityLabel("Show shirt")
                  .accessibilityIdentifier("tryon.shirt")
              }
              Text("Drag to turn. Pinch to look closer.")
                .font(.subheadline).foregroundStyle(.secondary)
              Text("Approximate shape over your scanned clothes. Fabric stretch and movement aren’t simulated. Back details weren’t captured.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
          }
        } else if let failure = model.failure {
          ContentUnavailableView {
            Label("Preview unavailable", systemImage: "tshirt")
          } description: { Text(failure) } actions: {
            Button("Try again") { attempt = UUID() }.buttonStyle(.borderedProminent)
          }
          .accessibilityIdentifier("tryon.failure")
        } else {
          VStack(spacing: 18) {
            ProgressView().controlSize(.large)
            Text(model.stage).font(.headline).multilineTextAlignment(.center)
              .accessibilityIdentifier("tryon.stage")
            Text("Using your saved body and shirt scans")
              .font(.subheadline).foregroundStyle(.secondary)
          }
          .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .navigationTitle(garment.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close try-on", systemImage: "xmark") { dismiss() }
            .accessibilityIdentifier("tryon.close")
        }
      }
    }
    .task(id: attempt) { await model.load(avatar: avatar, garment: garment, photoURL: photoURL) }
    .onDisappear { model.cancel() }
  }
}
