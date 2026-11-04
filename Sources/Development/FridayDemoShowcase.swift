#if DEBUG
import SwiftUI

struct FridayDemoShowcase: View {
    @StateObject private var selection = FridayDemoSelection()

    var body: some View {
        Group {
            if let preview = selection.preview {
                FridayGarmentDemoView(selection: selection, preview: preview)
                    .id(preview.productID)
            } else {
                ContentUnavailableView {
                    Label("Sample collection unavailable", systemImage: "tshirt")
                } description: {
                    Text(selection.failure ?? "Choose a supported sample to explore in 3D.")
                } actions: {
                    Button("Reload sample collection") { selection.reload() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("demo.reload")
                }
            }
        }
        .navigationTitle("FitCheck Demo Showcase")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
        .tint(.indigo)
    }
}

private struct FridayGarmentDemoView: View {
    @ObservedObject var selection: FridayDemoSelection
    let preview: CatalogIllustrativePreview
    @StateObject private var model: RendererLabModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(selection: FridayDemoSelection, preview: CatalogIllustrativePreview) {
        self.selection = selection
        self.preview = preview
        _model = StateObject(wrappedValue: RendererLabModel(presentation: preview.rendererPresentation))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline) {
                        Text("FitCheck").font(.title2.weight(.bold))
                        Spacer()
                        Text("3D SHOWCASE")
                            .font(.caption.weight(.semibold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("demo.showcase")
                }
                viewport
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : min(400, max(220, geometry.size.height * 0.47)))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        productHeading
                        viewControls
                        collection
                        nextChapter
                        Text("Fictional demo data · Not for sale. Generic mannequin, not your measured body. Sizes are labels: S and M use the same geometry. No physical drape or verified fit.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .accessibilityIdentifier("demo.controls")
            }
            .padding(.top, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear { model.close() }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    private var productHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(preview.productTitle) · \(preview.colorName) · \(preview.sizeLabel)")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("demo.product-context")
            Label("Generic mannequin · Drag to explore", systemImage: "hand.draw")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var viewport: some View {
        if let session = model.session, model.state == .ready,
           model.assetState == .procedural || model.assetState == .loaded,
           model.garmentFailure == nil {
            RendererViewport(session: session, model: model, sceneIdentifier: "demo.scene")
                .id(session.id)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if case .failed = model.state {
                        sceneRecovery
                    } else if case .failed = model.assetState {
                        garmentRecovery
                    } else if model.garmentFailure != nil, model.state == .ready {
                        garmentRecovery
                    } else if model.state == .suspended {
                        Label("3D preview paused", systemImage: "pause.circle")
                        Text("Your preview resumes when FitCheck is active.").font(.footnote)
                    } else {
                        ProgressView("Preparing sample in 3D…")
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var sceneRecovery: some View {
        VStack(spacing: 12) {
            Label("3D preview unavailable", systemImage: "cube.transparent")
                .font(.headline)
            Text("The graphics device could not prepare this scene. Retry to rebuild the preview.")
                .font(.subheadline)
            Button("Retry 3D preview") { model.retry() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("demo.retry")
        }
    }

    private var garmentRecovery: some View {
        VStack(spacing: 12) {
            Text("Sample garment unavailable").font(.headline)
            Text("This item's reviewed geometry could not be loaded. Retry or select another sample below.")
                .font(.subheadline)
            Button("Retry sample garment") { model.restoreGarment() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("demo.retry-garment")
        }
    }

    private var viewControls: some View {
        VStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { rotationButtons }
                VStack(alignment: .leading, spacing: 10) { rotationButtons }
            }
            Toggle("Show garment", isOn: Binding(
                get: { model.appearance.garmentVisible },
                set: { model.setGarmentVisible($0) }
            ))
            .accessibilityIdentifier("demo.garment-visible")
        }
        .disabled(model.state != .ready)
    }

    private var rotationButtons: some View {
        Group {
            Button { model.rotate(horizontal: -.pi / 6, vertical: 0) } label: {
                Label("Left", systemImage: "arrow.turn.up.left")
                    .frame(minHeight: 28)
            }
            .accessibilityLabel("Rotate left")
            .accessibilityIdentifier("demo.left")
            Button { model.rotate(horizontal: .pi / 6, vertical: 0) } label: {
                Label("Right", systemImage: "arrow.turn.up.right")
                    .frame(minHeight: 28)
            }
            .accessibilityLabel("Rotate right")
            .accessibilityIdentifier("demo.right")
            Button { model.resetView() } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 28)
            }
            .accessibilityLabel("Reset view")
            .accessibilityIdentifier("demo.reset")
        }
        .buttonStyle(.bordered)
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sample collection").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("DEMO DATA").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            ForEach(selection.products) { item in
                Button {
                    selection.select(productID: item.id, sizeID: preview.sizeID)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.product.category == .vest ? "square.stack.3d.up" : "tshirt")
                            .font(.title3)
                            .frame(width: 30)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.product.title).font(.subheadline.weight(.semibold))
                            Text(item.previews[0].colorName).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Circle()
                            .fill(item.previews[0].colorID == "sage"
                                  ? Color(red: 137 / 255, green: 151 / 255, blue: 134 / 255)
                                  : Color(red: 36 / 255, green: 54 / 255, blue: 75 / 255))
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        Image(systemName: item.id == preview.productID.productID ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(item.id == preview.productID.productID ? Color.indigo : .clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("demo.product.\(item.id)")
                .accessibilityValue(item.id == preview.productID.productID ? "Selected" : "Not selected")
                .accessibilityAddTraits(item.id == preview.productID.productID ? .isSelected : [])
            }
            HStack(spacing: 12) {
                Text("Size label").font(.subheadline)
                ForEach(selection.selectedProduct?.previews ?? [], id: \.sizeID) { option in
                    Button(option.sizeLabel) {
                        selection.select(productID: option.productID.productID, sizeID: option.sizeID)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .background(preview.sizeID == option.sizeID ? Color.indigo : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(preview.sizeID == option.sizeID ? Color.white : Color.primary)
                    .accessibilityLabel("Size \(option.sizeLabel)")
                    .accessibilityIdentifier("demo.size.\(option.sizeID)")
                    .accessibilityValue(preview.sizeID == option.sizeID ? "Selected, label only" : "Label only")
                    .accessibilityAddTraits(preview.sizeID == option.sizeID ? .isSelected : [])
                }
            }
            Text(selection.selectedProduct?.description ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nextChapter: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore the technology").font(.headline).accessibilityAddTraits(.isHeader)
            NavigationLink { FridayAvatarDemoView() } label: {
                Label("3D Avatar", systemImage: "square.3.layers.3d")
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("demo.open-avatar")
            NavigationLink { FridayReplayDemoView() } label: {
                Label("LiDAR Reconstruction Demo", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("demo.open-replay")
            Text("Two synthetic shape studies, separate from the clothing mannequin. No camera needed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
