import SwiftUI

struct BodyMeasurementsView: View {
  var store: OnYouStore
  var onSave: () -> Void
  @State private var fields: [BodyMeasurementField: String] = [:]
  @AppStorage("on-you.measurement-unit") private var unit = BodyMeasurementUnit.centimeters
  @FocusState private var focused: BodyMeasurementField?
  @State private var initialized = false

  private var parsed: BodyMeasurements? {
    BodyMeasurements.parse(fields, unit: unit)
  }

  var body: some View {
    Form {
      Section {
        BodySceneView(measurements: parsed ?? store.current ?? .example, angle: 0, reset: 0)
          .frame(height: 220)
          .listRowInsets(EdgeInsets())
          .accessibilityHidden(true)
      } footer: {
        Text("The model updates as you edit.")
      }
      Section {
        Picker("Units", selection: $unit) {
          ForEach(BodyMeasurementUnit.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: unit) { old, new in
          for field in BodyMeasurementField.allCases {
            let raw = (fields[field] ?? "").replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
            if let value = Double(raw), value.isFinite {
              let centimeters = (value * old.centimeters * 10).rounded() / 10
              fields[field] = display(centimeters / new.centimeters)
            }
          }
        }
        ForEach(BodyMeasurementField.allCases) { field in
          HStack {
            Text(field.title)
            Spacer()
            TextField(field.title, text: Binding(get: { fields[field] ?? "" }, set: { fields[field] = $0 }))
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .frame(minWidth: 60, maxWidth: 120)
              .focused($focused, equals: field)
              .accessibilityLabel("\(field.title) in \(unit.title.lowercased())")
              .accessibilityIdentifier("measurement.\(field.rawValue)")
            Text(unit.symbol).foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Body measurements")
      } footer: {
        if parsed == nil && initialized {
          Text("Enter a value for every measurement. Height: 120–220 cm; chest: 60–170; waist: 45–170; hips: 65–180; shoulders: 28–65.")
            .foregroundStyle(.red)
        } else {
          Text("Chest, waist, and hips are circumferences. Shoulders are measured straight across.")
        }
      }
      Section {
        NavigationLink { MeasurementGuideView() } label: { Label("How to measure", systemImage: "ruler") }
      }
      Section {
        Button(store.current == nil ? "Create my body" : "Save measurements") {
          guard let parsed, store.save(parsed) else { return }
          focused = nil
          onSave()
        }
        .disabled(parsed == nil)
        .accessibilityIdentifier("measurement.save")
      } footer: {
        Text("Saved on this iPhone. Each change is kept in History.")
      }
    }
    .navigationTitle("Measurements")
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") { focused = nil }
      }
    }
    .onAppear { if !initialized { reload() } }
    .onChange(of: store.current) { reload() }
  }

  private func reload() {
    let value = store.current ?? .example
    fields = Dictionary(uniqueKeysWithValues: BodyMeasurementField.allCases.map { ($0, display(value[$0] / unit.centimeters)) })
    initialized = true
  }

  private func display(_ value: Double) -> String {
    value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
  }
}

struct MeasurementGuideView: View {
  var body: some View {
    List {
      Section {
        Text("Use a flexible tape. Stand naturally and keep the tape level without pulling it tight.")
      }
      ForEach(BodyMeasurementField.allCases) { field in
        Section(field.title) { Text(field.instruction) }
      }
    }
    .navigationTitle("How to measure")
    .navigationBarTitleDisplayMode(.inline)
  }
}
