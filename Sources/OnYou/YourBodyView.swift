import SwiftUI

struct YourBodyView: View {
  var store: OnYouStore
  var edit: () -> Void
  @State private var viewAngle = BodyViewAngle.front
  @State private var reset = 0
  @State private var rotation: Float = 0
  @State private var fullScreen = false
  @AppStorage("on-you.wireframe") private var wireframe = false

  private var measurements: BodyMeasurements { store.current ?? .example }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 20) {
          VStack(alignment: .leading, spacing: 3) {
            Text(store.current == nil ? "Example body" : "Your body")
              .font(.title2.weight(.semibold))
            if store.current == nil {
              Button("Enter measurements", action: edit).font(.subheadline)
            } else {
              Text("From your latest measurements")
                .font(.subheadline).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          BodySceneView(measurements: measurements, angle: viewAngle.angle + rotation, reset: reset, wireframe: wireframe)
            .frame(height: max(300, min(510, geometry.size.height * 0.61)))
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

          Picker("View", selection: $viewAngle) {
            ForEach(BodyViewAngle.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .onChange(of: viewAngle) { rotation = 0; reset += 1 }

          HStack(spacing: 24) {
            Button("Rotate left", systemImage: "arrow.left") { rotation -= .pi / 6 }
            Button("Reset view", systemImage: "arrow.counterclockwise") { viewAngle = .front; rotation = 0; reset += 1 }
            Button("Rotate right", systemImage: "arrow.right") { rotation += .pi / 6 }
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.bordered)
          .controlSize(.regular)
          .frame(maxWidth: .infinity)

          HStack {
            summary("Height", measurements.height)
            Divider()
            summary("Chest", measurements.chest)
            Divider()
            summary("Waist", measurements.waist)
          }
          .fixedSize(horizontal: false, vertical: true)

        }
        .padding(20)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      }
      .background(Color(uiColor: .systemGroupedBackground))
    }
    .navigationTitle("On You")
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        NavigationLink { OnYouAboutView() } label: { Label("About", systemImage: "info") }
          .labelStyle(.iconOnly)
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Full screen", systemImage: "arrow.up.left.and.arrow.down.right") { fullScreen = true }
          .labelStyle(.iconOnly)
        Button("Edit measurements", systemImage: "ruler", action: edit)
          .labelStyle(.iconOnly)
      }
    }
    .fullScreenCover(isPresented: $fullScreen) {
      NavigationStack {
        BodySceneView(measurements: measurements, angle: viewAngle.angle + rotation, reset: reset, wireframe: wireframe)
          .background(Color(uiColor: .secondarySystemGroupedBackground))
          .navigationTitle("Your body")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { fullScreen = false } }
          }
      }
    }
  }

  private func summary(_ title: String, _ value: Double) -> some View {
    VStack(spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) cm")
        .font(.headline).monospacedDigit()
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

private enum BodyViewAngle: String, CaseIterable, Identifiable {
  case front = "Front", side = "Side", back = "Back"
  var id: String { rawValue }
  var angle: Float {
    switch self {
    case .front: 0
    case .side: .pi / 2
    case .back: .pi
    }
  }
}
