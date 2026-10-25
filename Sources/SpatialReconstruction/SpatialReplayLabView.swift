#if DEBUG
import SwiftUI

struct SpatialReplayLabView: View {
    @StateObject private var model = SpatialReplayLabModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let primary: [ReplayID] = [.columnA, .columnB, .missingDepth, .badCalibration, .conflictingViews]
    private static let additional = ReplayID.allCases.filter { !primary.contains($0) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                viewport
                    .frame(height: viewportHeight(geometry.size.height))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Simulated observations only", systemImage: "viewfinder")
                            .font(.headline)
                        Text("Synthetic LiDAR replay. No real person scanned. Geometry accuracy on physical hardware is unverified.")
                            .accessibilityIdentifier("replay.disclaimer")
                        Text(model.selected.title)
                            .font(.headline)
                            .accessibilityIdentifier("replay.selection")
                        Text("Source: first-party simulated rays, not a recorded scan.")
                            .font(.footnote)
                            .accessibilityIdentifier("replay.source")
                        if model.state == .ready {
                            Text("Observation-derived synthetic surface ready")
                                .accessibilityIdentifier("replay.ready")
                            rotationControls
                        }
                        ForEach(Self.primary) { replay in fixtureButton(replay) }
                        Button("Run synthetic reconstruction") { model.run() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.state == .processing || model.state == .suspended)
                            .accessibilityIdentifier("replay.run")
                        if let result = model.result, model.state == .ready {
                            Text("Completed reconstruction stages")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("replay.stages")
                            ForEach(result.stages, id: \.rawValue) { Text($0.rawValue) }
                            Text("Open fitted surface from supported synthetic sections. Unseen angular regions and ends remain unavailable; this is not a complete observed object.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Additional simulation cases") {
                            ForEach(Self.additional) { replay in fixtureButton(replay) }
                        }
                        .accessibilityIdentifier("replay.additional")
                        Text("Calibrated simulated rasters are unprojected, mapped and reconciled before fitting supported sections. No live scanner, saved profile, artifact storage or garment fitting is connected.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("replay.controls")
            }
            .padding(.top, 12)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("LiDAR Reconstruction Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    private func viewportHeight(_ available: CGFloat) -> CGFloat {
        let standard = min(350, max(170, available * 0.43))
        // Keep the full rejection category readable at accessibility sizes;
        // the controls remain independently scrollable below this status panel.
        if dynamicTypeSize.isAccessibilitySize, case .failed = model.state {
            return max(standard, available * 0.7)
        }
        return standard
    }

    private func fixtureButton(_ replay: ReplayID) -> some View {
        Button { model.select(replay) } label: {
            Label(replay.title, systemImage: model.selected == replay ? "checkmark.circle.fill" : "circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("replay.case.\(replay.rawValue)")
        .accessibilityValue(model.selected == replay ? "Selected" : "Not selected")
        .accessibilityAddTraits(model.selected == replay ? .isSelected : [])
    }

    @ViewBuilder
    private var viewport: some View {
        if let scene = model.session, model.state == .ready {
            GeometryViewport(session: scene, model: model, sceneIdentifier: "replay.scene",
                             sceneLabel: "Reconstructed synthetic depth surface, interactive 3D scene",
                             sceneHint: "Drag to rotate or use rotation buttons. No real person scanned.")
                .id(scene.id)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    switch model.state {
                    case .failed(let failure):
                        Text("Replay rejected")
                            .font(.headline)
                            .accessibilityIdentifier("replay.failure")
                        Text(failure.message)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("replay.failure.reason")
                        Text("No previous surface is displayed. Select a supported simulated replay to recover.")
                            .accessibilityIdentifier("replay.failure.recovery")
                    case .suspended: Text("Reconstruction paused while inactive")
                    case .idle: Text("Select a simulated replay to reconstruct")
                    case .processing, .ready:
                        ProgressView("Processing simulated depth observations")
                            .accessibilityIdentifier("replay.processing")
                    }
                }
                .padding()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("replay.status")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize { rotationButtons }
            else { HStack { rotationButtons } }
            Button("Reset View", systemImage: "arrow.counterclockwise") { model.resetView() }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("replay.reset")
        }
    }

    private var rotationButtons: some View {
        Group {
            Button("Rotate left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }
                .accessibilityIdentifier("replay.left")
            Button("Rotate right") { model.rotate(horizontal: .pi / 6, vertical: 0) }
                .accessibilityIdentifier("replay.right")
        }
        .buttonStyle(.bordered)
    }
}

extension SpatialReplayLabModel: GeometryViewportControlling {
    var viewportValue: String { "Replay-derived \(selected.title)" }
}
#endif
