#if DEBUG
import SwiftUI

struct FridayAvatarDemoView: View {
    @StateObject private var model = AvatarGeometryLabModel(makeScene: {
        try RendererSceneSession(geometry: $0, fitSurface: true)
    })
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                scene
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : min(390, max(220, geometry.size.height * 0.48)))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(eyebrow: "SYNTHETIC AVATAR", title: "Shape, in three dimensions", symbol: "cube.transparent")
                        Text("An illustrative geometry study built from authored synthetic sections—not a scan or a complete body model.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("demo.avatar.disclaimer")
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                shapeButton(.surfaceA, title: "Shape A", identifier: "demo.avatar.shape-a")
                                shapeButton(.surfaceB, title: "Shape B", identifier: "demo.avatar.shape-b")
                            }
                        } else {
                            HStack(spacing: 10) {
                                shapeButton(.surfaceA, title: "Shape A", identifier: "demo.avatar.shape-a")
                                shapeButton(.surfaceB, title: "Shape B", identifier: "demo.avatar.shape-b")
                            }
                        }
                        status
                        if model.state == .ready { rotationControls }
                        Text("Only supported synthetic sections are represented. Interpolated areas are estimates; unseen regions and ends remain unknown. No camera, scanner, personal measurements, profile, or saved avatar is involved.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .accessibilityIdentifier("demo.avatar.controls")
            }
            .padding(.top, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("3D Avatar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    @ViewBuilder private var scene: some View {
        if let session = model.session, model.state == .ready {
            GeometryViewport(session: session, model: model, sceneIdentifier: "demo.avatar.scene",
                             sceneLabel: "Synthetic avatar geometry, interactive three-dimensional scene",
                             sceneHint: "Drag to rotate. This illustrative surface is not reconstructed from a person.")
                .id(session.id)
        } else {
            statusPanel
        }
    }

    @ViewBuilder private var status: some View {
        if model.state == .ready {
            Label("Synthetic geometry ready", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.indigo)
                .accessibilityIdentifier("demo.avatar.ready")
        }
    }

    @ViewBuilder private var statusPanel: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .failed(let failure):
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                Text("Surface unavailable").font(.headline)
                Text(failure.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("No previous surface is displayed. Retry to generate the selected synthetic shape.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry", systemImage: "arrow.clockwise") { model.generate() }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                    .accessibilityIdentifier("demo.avatar.retry")
            case .suspended:
                Label("Paused while app is inactive", systemImage: "pause.circle").font(.headline)
            case .idle:
                Text("Preparing synthetic geometry…").font(.headline)
            case .processing, .ready:
                ProgressView().tint(.indigo)
                Text("Generating \(model.selected == .surfaceA ? "Shape A" : "Shape B")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func shapeButton(_ fixture: GeometryFixtureID, title: String, identifier: String) -> some View {
        let selected = model.selected == fixture
        return Button { model.select(fixture) } label: {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.borderedProminent).tint(selected ? .indigo : Color(uiColor: .tertiarySystemBackground))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore the form").font(.headline).accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                Button("Rotate left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }.accessibilityIdentifier("demo.avatar.left")
                Button("Rotate right") { model.rotate(horizontal: .pi / 6, vertical: 0) }.accessibilityIdentifier("demo.avatar.right")
            } else {
                HStack {
                    Button("Left", systemImage: "arrow.turn.up.left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }
                        .accessibilityLabel("Rotate left").accessibilityIdentifier("demo.avatar.left")
                    Button("Right", systemImage: "arrow.turn.up.right") { model.rotate(horizontal: .pi / 6, vertical: 0) }
                        .accessibilityLabel("Rotate right").accessibilityIdentifier("demo.avatar.right")
                    Spacer(minLength: 0)
                    Button("Reset", systemImage: "arrow.counterclockwise") { model.resetView() }.accessibilityIdentifier("demo.avatar.reset")
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                Button("Reset view", systemImage: "arrow.counterclockwise") { model.resetView() }.accessibilityIdentifier("demo.avatar.reset")
            }
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }
}

struct FridayReplayDemoView: View {
    @StateObject private var model = SpatialReplayLabModel(makeScene: {
        try RendererSceneSession(replay: $0, fitSurface: true)
    })
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 14) {
                scene
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : min(390, max(220, geometry.size.height * 0.48)))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
                    .padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(eyebrow: "SIMULATED DEPTH REPLAY", title: "From samples to surface", symbol: "view.3d")
                        Text("A synthetic reconstruction exercise from simulated depth observations. It does not depict a real person or a recorded scan.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("demo.replay.disclaimer")
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                replayButton(.columnA, title: "Replay A", identifier: "demo.replay.shape-a")
                                replayButton(.columnB, title: "Replay B", identifier: "demo.replay.shape-b")
                            }
                        } else {
                            HStack(spacing: 10) {
                                replayButton(.columnA, title: "Replay A", identifier: "demo.replay.shape-a")
                                replayButton(.columnB, title: "Replay B", identifier: "demo.replay.shape-b")
                            }
                        }
                        status
                        if model.state == .ready { rotationControls }
                        Text("The displayed surface is fitted only from supported simulated observations. Unobserved angular regions and ends are unavailable; physical-device accuracy is unverified. No live scanner or camera is connected.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 22).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .accessibilityIdentifier("demo.replay.controls")
            }
            .padding(.top, 12)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("LiDAR Reconstruction Demo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    @ViewBuilder private var scene: some View {
        if let session = model.session, model.state == .ready {
            GeometryViewport(session: session, model: model, sceneIdentifier: "demo.replay.scene",
                             sceneLabel: "Synthetic depth reconstruction, interactive three-dimensional scene",
                             sceneHint: "Drag to rotate. This surface is reconstructed from simulated observations only.")
                .id(session.id)
        } else { statusPanel }
    }

    @ViewBuilder private var status: some View {
        if model.state == .ready {
            Label("Synthetic reconstruction ready", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.indigo)
                .accessibilityIdentifier("demo.replay.ready")
        }
    }

    @ViewBuilder private var statusPanel: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .failed(let failure):
                Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.orange)
                Text("Replay unavailable").font(.headline)
                Text(failure.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("No previous surface is displayed. Retry the selected simulated replay.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Retry", systemImage: "arrow.clockwise") { model.run() }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                    .accessibilityIdentifier("demo.replay.retry")
            case .suspended:
                Label("Paused while app is inactive", systemImage: "pause.circle").font(.headline)
            case .idle:
                Text("Preparing synthetic replay…").font(.headline)
            case .processing, .ready:
                ProgressView().tint(.indigo)
                Text("Reconstructing \(model.selected == .columnA ? "Replay A" : "Replay B")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func replayButton(_ replay: ReplayID, title: String, identifier: String) -> some View {
        let selected = model.selected == replay
        return Button { model.select(replay) } label: {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.borderedProminent).tint(selected ? .indigo : Color(uiColor: .tertiarySystemBackground))
        .foregroundStyle(selected ? Color.white : Color.primary)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Explore the reconstruction").font(.headline).accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                Button("Rotate left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }.accessibilityIdentifier("demo.replay.left")
                Button("Rotate right") { model.rotate(horizontal: .pi / 6, vertical: 0) }.accessibilityIdentifier("demo.replay.right")
            } else {
                HStack {
                    Button("Left", systemImage: "arrow.turn.up.left") { model.rotate(horizontal: -.pi / 6, vertical: 0) }
                        .accessibilityLabel("Rotate left").accessibilityIdentifier("demo.replay.left")
                    Button("Right", systemImage: "arrow.turn.up.right") { model.rotate(horizontal: .pi / 6, vertical: 0) }
                        .accessibilityLabel("Rotate right").accessibilityIdentifier("demo.replay.right")
                    Spacer(minLength: 0)
                    Button("Reset", systemImage: "arrow.counterclockwise") { model.resetView() }.accessibilityIdentifier("demo.replay.reset")
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                Button("Reset view", systemImage: "arrow.counterclockwise") { model.resetView() }.accessibilityIdentifier("demo.replay.reset")
            }
        }
        .buttonStyle(.bordered)
        .tint(.indigo)
    }
}

private func header(eyebrow: String, title: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Label(eyebrow, systemImage: symbol)
            .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.indigo)
        Text(title)
            .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

#endif
