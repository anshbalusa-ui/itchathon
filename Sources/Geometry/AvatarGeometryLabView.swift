#if DEBUG
import SwiftUI

struct AvatarGeometryLabView: View {
    @StateObject private var model = AvatarGeometryLabModel()
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
                        Label("Synthetic geometry only", systemImage: "cube.transparent")
                            .font(.headline)
                        Text("Synthetic, illustrative and not reconstructed from a real person.")
                            .accessibilityIdentifier("geometry.disclaimer")
                        Text(model.selected.title)
                            .font(.headline)
                            .accessibilityIdentifier("geometry.selection")
                        if model.state == .ready {
                            Text("Generated surface ready")
                                .accessibilityIdentifier("geometry.ready")
                            rotationControls
                        }
                        Text("Reviewed synthetic fixtures")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(GeometryFixtureID.allCases) { fixture in
                            Button { model.select(fixture) } label: {
                                Label(fixture.title, systemImage: model.selected == fixture ? "checkmark.circle.fill" : "circle")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("geometry.fixture.\(fixture.rawValue)")
                            .accessibilityValue(model.selected == fixture ? "Selected" : "Not selected")
                            .accessibilityAddTraits(model.selected == fixture ? .isSelected : [])
                        }
                        Button(model.isFailure ? "Retry synthetic generation" : "Generate synthetic surface") {
                            model.generate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.state == .processing || model.state == .suspended)
                        .accessibilityIdentifier("geometry.generate")
                        Text("Only authored synthetic sections are supported. The surface between them is interpolation, not observation. Ends and other regions remain unknown and open.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("No camera, saved profile, garment fitting or body measurements are used. Unverified scanner evidence is rejected; this lab cannot create a saved personal avatar.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("geometry.controls")
            }
            .padding(.top, 12)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Avatar Geometry Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    @ViewBuilder
    private var viewport: some View {
        if let session = model.session, model.state == .ready {
            GeometryViewport(session: session, model: model)
                .id(session.id)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    switch model.state {
                    case .failed(let failure):
                        Text("Synthetic surface unavailable")
                            .font(.headline)
                            .accessibilityIdentifier("geometry.failure")
                        Text(failure.message)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("No previous surface is displayed. Choose a valid synthetic fixture or retry.")
                            .font(.footnote)
                    case .suspended:
                        Text("Generation and rendering paused while inactive")
                    case .idle, .processing, .ready:
                        ProgressView("Generating synthetic surface")
                            .accessibilityIdentifier("geometry.processing")
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                rotationButtons
            } else {
                HStack { rotationButtons }
            }
            Button("Reset View", systemImage: "arrow.counterclockwise") { model.resetView() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("geometry.reset-view")
        }
    }

    private var rotationButtons: some View {
        Group {
            Button("Rotate left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }
                .accessibilityIdentifier("geometry.left")
            Button("Rotate right") { model.rotate(horizontal: .pi / 6, vertical: 0) }
                .accessibilityIdentifier("geometry.right")
        }
        .buttonStyle(.bordered)
    }
}

private extension AvatarGeometryLabModel {
    var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }
}
#endif
