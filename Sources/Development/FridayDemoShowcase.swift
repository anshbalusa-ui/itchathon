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
    @StateObject private var model: HumanShowcaseModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(selection: FridayDemoSelection, preview: CatalogIllustrativePreview) {
        self.selection = selection
        self.preview = preview
        _model = StateObject(wrappedValue: HumanShowcaseModel(preview: preview))
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline) {
                        Text("FitCheck").font(.title2.weight(.bold))
                        Spacer()
                        measurementEntry
                    }
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("demo.showcase")
                }
                viewport
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : min(400, max(220, geometry.size.height * 0.47)))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if dynamicTypeSize.isAccessibilitySize { measurementEntry }
                        productHeading
                        viewControls
                        collection
                        bodyInspection
                        nextChapter
                        Text("Fictional demo data · Not for sale. Authored human model, not your measured body. S and M are labels using the same sample geometry. No verified fit or physical cloth simulation.")
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

    private var measurementEntry: some View {
        NavigationLink {
            MeasurementAvatarDemoView()
        } label: {
            Label("Create avatar", systemImage: "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel("Create avatar from demo measurements")
        .accessibilityIdentifier("demo.open-measurements")
    }

    private var productHeading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(preview.productTitle) · \(preview.colorName) · \(preview.sizeLabel)")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("demo.product-context")
            Label("Illustrative human · Drag to explore", systemImage: "hand.draw")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var viewport: some View {
        if let session = model.session, model.state == .ready {
            GeometryViewport(session: session, model: model, sceneIdentifier: "demo.scene",
                             sceneLabel: "Human avatar and sample clothing, interactive 3D scene",
                             sceneHint: "Drag to rotate or select a body region below to inspect it. Not a personal scan.")
                .id(session.id)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    if case .failed = model.state {
                        sceneRecovery
                    } else if model.state == .loading {
                        ProgressView("Preparing human model…")
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
            Label("Human preview unavailable", systemImage: "person.crop.rectangle")
                .font(.headline)
            if case .failed(let message) = model.state {
                Text(message).font(.subheadline)
            }
            Button("Retry 3D preview") { model.retry() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("demo.retry")
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

    private var bodyInspection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Inspect the human model").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Choose a region to move closer. Drag to look around it.")
                .font(.subheadline).foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(HumanBodyRegion.allCases) { regionButton($0) }
                }
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(0..<3) { row in
                        GridRow {
                            ForEach(0..<3) { column in
                                let index = row * 3 + column
                                if index < HumanBodyRegion.allCases.count {
                                    regionButton(HumanBodyRegion.allCases[index])
                                }
                            }
                        }
                    }
                }
            }
            Text(model.regionSummary)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("demo.region-summary")
            Toggle("Show sample fit map", isOn: Binding(
                get: { model.fitMapVisible }, set: { model.setFitMapVisible($0) }
            ))
            .accessibilityIdentifier("demo.fit-map")
            if model.fitMapVisible {
                HStack(spacing: 16) {
                    Label("Closer", systemImage: "circle.fill").foregroundStyle(.red)
                    Label("More room", systemImage: "circle.fill").foregroundStyle(.green)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            Text("Illustrative sample spacing only — not your body, a pressure simulation or verified fit.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("demo.fit-disclaimer")
        }
        .disabled(model.state != .ready)
    }

    private func regionButton(_ region: HumanBodyRegion) -> some View {
        Button { model.focus(region) } label: {
            Text(region.title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .tint(model.region == region ? .indigo : .primary)
        .accessibilityIdentifier("demo.region.\(region.rawValue)")
        .accessibilityValue(model.region == region ? "Selected" : "Not selected")
        .accessibilityAddTraits(model.region == region ? .isSelected : [])
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
                Label("Synthetic surface study", systemImage: "square.3.layers.3d")
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
            Text("Separate reconstruction studies, not the authored human model above. No camera needed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
