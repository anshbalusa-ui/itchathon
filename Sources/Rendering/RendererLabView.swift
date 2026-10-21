#if DEBUG
import SwiftUI

struct RendererLabView: View {
    @StateObject private var model: RendererLabModel
    private let presentation: RendererPresentation

    init(presentation: RendererPresentation = .lab) {
        self.presentation = presentation
        _model = StateObject(wrappedValue: RendererLabModel(presentation: presentation))
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                viewport
                    .frame(height: min(350, max(170, geometry.size.height * 0.43)))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Generic visualization fixture", systemImage: "cube.transparent")
                            .font(.headline)
                        if let context = presentation.context {
                            Text(context)
                                .accessibilityIdentifier("renderer.product-context")
                            Text("Size label only; the same illustrative geometry is used for every size.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Not your body or a retailer garment. No sizing, physical drape or fit is represented.")
                            .foregroundStyle(.secondary)
                        if model.state == .ready {
                            controls
                        }
                        Text(presentation.context == nil
                             ? "Drag the scene to rotate. Rotation buttons provide an alternative. This lab uses no camera, scan or saved profile."
                             : "Illustrative only: no body scan, measurements, fit, or physical drape is represented.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("renderer.controls")
            }
            .padding(.top, 12)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    @ViewBuilder
    private var viewport: some View {
        if let session = model.session, model.state == .ready {
            RendererViewport(session: session, model: model)
                .id(session.id)
        } else {
            ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "cube.transparent")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                switch model.state {
                case .failed(let failure):
                    Text("3D scene unavailable").font(.headline)
                    Text(failure.localizedDescription).multilineTextAlignment(.center)
                    Button("Retry scene") { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("renderer.retry")
                case .suspended:
                    Text("Rendering paused while the app is inactive")
                case .idle, .ready:
                    ProgressView("Preparing generic scene")
                }
            }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("View controls").font(.headline).accessibilityAddTraits(.isHeader)
            // Four fixed controls need no virtualization; keep offscreen buttons discoverable.
            VStack(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    horizontalRotationButtons
                    verticalRotationButtons
                } else {
                    HStack(spacing: 12) { horizontalRotationButtons }
                    HStack(spacing: 12) { verticalRotationButtons }
                }
            }
            Button("Reset View", systemImage: "arrow.counterclockwise") { model.resetView() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("renderer.reset-view")

            Divider()
            Text("Illustrative garment").font(.headline).accessibilityAddTraits(.isHeader)
            if let failure = model.garmentFailure {
                Text("Garment unavailable. \(failure.localizedDescription)")
                    .foregroundStyle(.secondary)
                Button("Restore sample garment") { model.restoreGarment() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("renderer.restore-garment")
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Show illustrative garment")
                            .accessibilityHidden(true)
                        garmentVisibilityToggle.labelsHidden()
                    }
                } else {
                    garmentVisibilityToggle
                }
                if presentation.allowsMaterialChanges {
                    Text("Material color").font(.subheadline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 140), spacing: 12)], spacing: 12) {
                        ForEach(RendererMaterial.allCases) { material in
                            Button {
                                model.selectMaterial(material)
                            } label: {
                                Label(material.title, systemImage: model.appearance.material == material ? "checkmark.circle.fill" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("renderer.material.\(material.rawValue)")
                            .accessibilityValue(model.appearance.material == material ? "Selected" : "Not selected")
                            .accessibilityAddTraits(model.appearance.material == material ? .isSelected : [])
                        }
                    }
                    .disabled(!model.appearance.garmentVisible)
                } else {
                    Text("Illustrative color: \(model.appearance.material.title). Go back to change the selected variant.")
                        .accessibilityIdentifier("renderer.locked-material")
                }
                Button("Reset Appearance", systemImage: "arrow.counterclockwise") { model.resetAppearance() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("renderer.reset-appearance")
            }
        }
    }

    private var garmentVisibilityToggle: some View {
        Toggle("Show illustrative garment", isOn: Binding(
            get: { model.appearance.garmentVisible },
            set: { model.setGarmentVisible($0) }
        ))
        .accessibilityLabel("Show illustrative garment")
        .accessibilityIdentifier("renderer.garment")
    }

    private var horizontalRotationButtons: some View {
        Group {
            rotationButton("Rotate left", icon: "arrow.turn.up.left", horizontal: -.pi / 6, vertical: 0, id: "renderer.left")
            rotationButton("Rotate right", icon: "arrow.turn.up.right", horizontal: .pi / 6, vertical: 0, id: "renderer.right")
        }
    }

    private var verticalRotationButtons: some View {
        Group {
            rotationButton("Tilt up", icon: "arrow.up", horizontal: 0, vertical: -.pi / 18, id: "renderer.up")
            rotationButton("Tilt down", icon: "arrow.down", horizontal: 0, vertical: .pi / 18, id: "renderer.down")
        }
    }

    private func rotationButton(_ title: String, icon: String, horizontal: Float, vertical: Float, id: String) -> some View {
        Button {
            model.rotate(horizontal: horizontal, vertical: vertical)
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                } else {
                    Label(title, systemImage: icon)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }
}
#endif
