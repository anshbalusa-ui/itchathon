import SwiftUI

struct TryOnView: View {
  var avatar: AvatarScanAsset
  var garment: ClosetGarment
  var photoURL: URL
  @State private var model = TryOnModel()
  @State private var attempt = UUID()
  @State private var showingShirt = true
  @State private var camera: BodySceneCameraRequest?
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    Group {
      if let result = model.result {
        GeometryReader { geometry in
          VStack(spacing: 0) {
            BodySceneView(measurements: .example,
              scan: ScannedBodySource(url: avatar.url,scene: result.avatar),
              tryOn: result, showingGarment: showingShirt, cameraRequest: camera, isActive: scenePhase == .active)
              .frame(height: typeSize.isAccessibilitySize ? 230 : max(220, geometry.size.height * 0.61))
              .accessibilityIdentifier("tryon.scene")
            ScrollView {
              VStack(alignment: .leading, spacing: 18) {
                HStack {
                  if typeSize.isAccessibilitySize { Text("3D illustration").font(.headline) }
                  else { Label("Illustrative drape",systemImage: "tshirt").font(.headline) }
                  Spacer(minLength: 12)
                  Toggle("Shirt", isOn: $showingShirt)
                    .labelsHidden().accessibilityLabel("Show shirt")
                    .accessibilityIdentifier("tryon.shirt")
                }
                if typeSize.isAccessibilitySize {
                  VStack(spacing: 8) { rotationButtons }
                } else {
                  HStack(spacing: 10) { rotationButtons }
                }
                if typeSize.isAccessibilitySize {
                  VStack(spacing: 8) { inspectionButtons }
                } else {
                  HStack(spacing: 10) { inspectionButtons }
                }
                Text("Drag to turn · Pinch to look closer")
                  .font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                  Text(result.shape.needsRoom ? "Closer to the captured surface" : "Looser illustrative outline")
                    .font(.subheadline.weight(.medium))
                  Text(result.shape.belowHips ? "Hem extends below the lower-body reference" : "Hem ends above the lower-body reference")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("A geometric illustration over the clothes in your body scan—not verified fit or pressure. Fabric stretch and movement aren’t simulated. The plain rear is inferred; back details weren’t captured.")
                  .font(.footnote).foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              .padding(20).frame(maxWidth: 620)
              .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("tryon.controls")
            .background(.bar)
          }
        }
      } else if let failure = model.failure {
        GeometryReader { geometry in
          ScrollView {
            VStack(spacing: 20) {
              Image(systemName: "tshirt").font(.system(size: 48,weight: .light))
                .foregroundStyle(.secondary).accessibilityHidden(true)
              Text("Preview unavailable").font(.title2.bold())
              Text(failure).foregroundStyle(.secondary).fixedSize(horizontal: false,vertical: true)
              Button("Try again") { showingShirt = true; attempt = UUID() }
                .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("tryon.retry")
              Button("Back to garment") { dismiss() }
                .frame(minHeight: 44).accessibilityIdentifier("tryon.back-to-garment")
            }
            .multilineTextAlignment(.center).frame(maxWidth: 560)
            .frame(maxWidth: .infinity,minHeight: max(0,geometry.size.height-48))
            .padding(24)
          }
        }
        .accessibilityIdentifier("tryon.failure")
      } else {
        VStack(spacing: 18) {
          ProgressView().controlSize(.large)
          Text(model.stage).font(.headline).multilineTextAlignment(.center)
            .accessibilityIdentifier("tryon.stage")
          Text("Preparing your saved avatar and shirt")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .navigationTitle(garment.name)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar(.hidden,for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Close try-on", systemImage: "xmark") { dismiss() }
          .accessibilityIdentifier("tryon.close")
      }
    }
    .task(id: attempt) { await model.load(avatar: avatar, garment: garment, photoURL: photoURL) }
    .onDisappear { model.cancel() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { attempt = UUID() }
      else { model.cancel() }
    }
  }

  private var rotationButtons: some View {
    Group {
      viewButton("Left", symbol: "rotate.left", id: "tryon.left", action: .turn(-.pi / 4))
      viewButton("Reset", symbol: "arrow.counterclockwise", id: "tryon.reset", action: .reset)
      viewButton("Right", symbol: "rotate.right", id: "tryon.right", action: .turn(.pi / 4))
    }
  }

  private var inspectionButtons: some View {
    Group {
      viewButton("Front", symbol: "person", id: "tryon.front", action: .front)
      viewButton("Back", symbol: "person.fill", id: "tryon.back", action: .back)
    }
  }

  private func viewButton(_ title: String, symbol: String, id: String, action: BodySceneCameraRequest.Action) -> some View {
    Button { camera = BodySceneCameraRequest(action: action) } label: {
      Label(title, systemImage: symbol).frame(maxWidth: .infinity, minHeight: 30)
    }
    .buttonStyle(.bordered).controlSize(.regular).accessibilityIdentifier(id)
  }
}
