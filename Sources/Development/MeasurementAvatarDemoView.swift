#if DEBUG
import SwiftUI
private enum MeasurementFieldError: LocalizedError {
    case invalidNumber
    var errorDescription: String? { "Enter a number for each measurement, using centimetres." }
}


struct MeasurementAvatarDemoView: View {
    @StateObject private var model = MeasurementAvatarModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?
    @State private var showingResult = false
    @State private var height = "180"
    @State private var chest = "96"
    @State private var waist = "80"
    @State private var hips = "98"
    @State private var shoulders = "43"
    @State private var validationMessage: String?

    private enum Field: Hashable { case height, chest, waist, hips, shoulders }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 12) {
                if showingResult {
                    scene
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 210 : min(390, max(210, geometry.size.height * 0.48)))
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .padding(.horizontal, 16)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if showingResult { resultContent } else { editorContent }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .accessibilityIdentifier(showingResult ? "measurements.controls" : "measurements.form")
                .id(showingResult)
            }
            .padding(.top, 8)
        }
        .background(Color(uiColor: .systemBackground))
        .tint(.indigo)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showingResult {
                VStack(alignment: .leading, spacing: 8) {
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.subheadline).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("measurements.error")
                    }
                    generateButton
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("measurements.actions")
            }
        }
        .navigationTitle("Measurement avatar demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .accessibilityIdentifier("measurements.done")
            }
        }
        .onAppear { model.open(isActive: scenePhase == .active) }
        .onDisappear {
            model.close()
            showingResult = false
            setSample(.sampleA)
        }
        .onChange(of: scenePhase) { _, phase in model.setActive(phase == .active) }
    }

    @ViewBuilder private var scene: some View {
        if showingResult, let session = model.session, model.state == .ready {
            GeometryViewport(session: session, model: model, sceneIdentifier: "measurements.scene",
                             sceneLabel: "Generated generic human illustration, interactive 3D scene",
                             sceneHint: "Drag to rotate. Shaped from the values you entered; not a scan or exact person.")
                .id(session.id)
        } else {
            VStack(spacing: 12) {
                switch model.state {
                case .generating:
                    ProgressView("Generating your illustration…")
                case .suspended:
                    Label("Preview paused", systemImage: "pause.circle")
                    Text("The preview resumes when FitCheck is active.").font(.footnote)
                case .failed(let message) where showingResult:
                    Label("Preview unavailable", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message).font(.subheadline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("measurements.error")
                    Button("Retry") { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("measurements.retry")
                default:
                    Image(systemName: "figure.stand")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(showingResult ? "Preparing your illustration…" : "Your illustration appears here")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create a demo avatar")
                    .font(.title2.weight(.semibold))
                Text("Adjust five measurements to shape the 3D human. All values are in centimetres; the scanner is separate.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { sampleButtons }
            } else {
                HStack(spacing: 10) { sampleButtons }
            }
            VStack(spacing: 10) {
                measurementField("Height", value: $height, field: .height, identifier: "measurements.height")
                measurementField("Chest circumference", value: $chest, field: .chest, identifier: "measurements.chest")
                measurementField("Waist circumference", value: $waist, field: .waist, identifier: "measurements.waist")
                measurementField("Hip circumference", value: $hips, field: .hips, identifier: "measurements.hips")
                measurementField("Shoulder width", value: $shoulders, field: .shoulders, identifier: "measurements.shoulders")
            }
            Text("Editable demo data · Nothing is scanned, saved or uploaded. These values shape a generic model, not an exact person.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var generateButton: some View {
        Button {
            focusedField = nil
            generate()
        } label: {
            Label("Generate avatar", systemImage: "sparkles")
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("measurements.generate")
    }

    private var sampleButtons: some View {
        Group {
            Button("Sample A") { setSample(.sampleA) }
                .accessibilityIdentifier("measurements.sample-a")
            Button("Sample B") { setSample(.sampleB) }
                .accessibilityIdentifier("measurements.sample-b")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your generated avatar")
                .font(.title2.weight(.semibold))
            if model.state == .ready {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        rotationButton("Left", id: "measurements.left") { model.rotateLeft() }
                        rotationButton("Right", id: "measurements.right") { model.rotateRight() }
                        rotationButton("Reset", id: "measurements.reset") { model.resetView() }
                    }
                } else {
                    HStack(spacing: 10) {
                        rotationButton("Left", id: "measurements.left") { model.rotateLeft() }
                        rotationButton("Right", id: "measurements.right") { model.rotateRight() }
                        rotationButton("Reset", id: "measurements.reset") { model.resetView() }
                    }
                }
                Toggle("Show illustrative shirt", isOn: Binding(
                    get: { model.appearance.garmentVisible },
                    set: { model.setShirtVisible($0) }
                ))
                .accessibilityIdentifier("measurements.shirt")
            }
            if !model.summary.isEmpty {
                Text(model.summary)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("measurements.summary")
            }
            Text("Generic measurement-shaped demonstration—not a scan, exact person, validated fit, or size recommendation.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Edit measurements") {
                model.editMeasurements()
                showingResult = false
                validationMessage = nil
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("measurements.edit")
        }
    }

    private func measurementField(_ title: String, value: Binding<String>, field: Field, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize { Text(title) }
            HStack(spacing: 12) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(title).frame(maxWidth: .infinity, alignment: .leading)
                }
                TextField(title, text: value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
                    .frame(minWidth: 92, minHeight: 30)
                    .accessibilityLabel("\(title), centimetres")
                    .accessibilityIdentifier(identifier)
                Text("cm").foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func rotationButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    private func setSample(_ input: MeasurementAvatarInput) {
        focusedField = nil
        height = String(Int(input.heightCM))
        chest = String(Int(input.chestCM))
        waist = String(Int(input.waistCM))
        hips = String(Int(input.hipsCM))
        shoulders = String(Int(input.shouldersCM))
        validationMessage = nil
    }

    private func generate() {
        do {
            let height = try number(height)
            let chest = try number(chest)
            let waist = try number(waist)
            let hips = try number(hips)
            let shoulders = try number(shoulders)
            let input = try MeasurementAvatarInput(heightCM: height, chestCM: chest, waistCM: waist,
                                                  hipsCM: hips, shouldersCM: shoulders)
            validationMessage = nil
            showingResult = true
            model.generate(input)
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func number(_ text: String) throws -> Double {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { throw MeasurementFieldError.invalidNumber }
        return value
    }
}
#endif
