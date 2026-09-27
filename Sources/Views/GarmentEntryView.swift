import SwiftUI

struct GarmentEntryView: View {
  enum Purpose {
    case favorite
    case candidate

    var title: String { self == .favorite ? "My Fit" : "Check a Garment" }
  }

  @Environment(\.dismiss) private var dismiss
  @AppStorage("fitcheck.preferredUnit") private var unitRaw = LengthUnit.centimeters.rawValue

  var purpose: Purpose
  var onSave: (GarmentProfile) throws -> Void

  @State private var draft: GarmentProfile
  @State private var chestValid = true
  @State private var shoulderValid = true
  @State private var lengthValid = true
  @State private var waistValid = true
  @State private var sourceRaw = MeasurementSource.manual.rawValue
  @State private var showScanner = false
  @State private var errorMessage: String?

  init(purpose: Purpose, initial: GarmentProfile = GarmentProfile(), onSave: @escaping (GarmentProfile) throws -> Void) {
    self.purpose = purpose
    self.onSave = onSave
    var copy = initial
    if copy.name == "Scanned garment" { copy.name = "" }
    _draft = State(initialValue: copy)
  }

  private var unit: LengthUnit { LengthUnit(rawValue: unitRaw) ?? .centimeters }

  var body: some View {
    Form {
      Section {
        TextField("Garment name", text: $draft.name)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .accessibilityLabel("Garment name")
      } header: {
        Text(purpose == .favorite ? "Your reference shirt" : "Garment to check")
      } footer: {
        Text(purpose == .favorite
             ? "Choose a shirt whose fit you know and like. Future comparisons use its measurements as your preference."
             : "Compare this shirt against your saved body and favorite shirt.")
      }

      Section {
        Picker("Units", selection: $unitRaw) {
          ForEach(LengthUnit.allCases) { option in
            Text(option == .centimeters ? "Centimeters" : "Inches")
              .tag(option.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } footer: {
        Text("Measure the shirt laid flat without stretching it. Use the same method for both shirts.")
      }

      Section("Shirt measurements") {
        MeasurementField(title: "Chest width", meters: $draft.chestFlat, unit: unit, isValid: $chestValid) {
          markEdited(.garmentChestFlat)
        }
        MeasurementField(title: "Shoulders", meters: $draft.shoulderWidth, unit: unit, isValid: $shoulderValid) {
          markEdited(.garmentShoulderWidth)
        }
        MeasurementField(title: "Length", meters: $draft.length, unit: unit, isValid: $lengthValid) {
          markEdited(.garmentLength)
        }
        MeasurementField(title: "Waist width", meters: $draft.waistFlat, unit: unit, required: false, isValid: $waistValid) {
          markEdited(.garmentWaistFlat)
          if draft.waistFlat == 0 { draft.waistAtNavel = nil }
        }
        if draft.waistFlat > 0 {
          Toggle("Waist measured at navel level", isOn: Binding(
            get: { draft.waistAtNavel == true },
            set: { draft.waistAtNavel = $0 }
          ))
        }
      }

      Section {
        Button("Measure with Camera", systemImage: "camera.viewfinder") {
          showScanner = true
        }
      } footer: {
        Text("A helper can aim the center reticle at each edge of a shirt laid flat. Review every value before saving.")
      }

      Section {
        Picker("Source of values you enter", selection: $sourceRaw) {
          Text("Measured by me").tag(MeasurementSource.manual.rawValue)
          Text("Another measurement").tag(MeasurementSource.external.rawValue)
          Text("Retailer chart").tag(MeasurementSource.retailer.rawValue)
        }
        .onChange(of: sourceRaw) { _, value in
          guard let selected = MeasurementSource(rawValue: value),
                var origins = draft.origins else { return }
          for key in origins.keys {
            guard var origin = origins[key], origin.source != .garmentScan else { continue }
            origin.source = selected
            origin.verifiedWithTape = false
            origin.observedErrorMeters = nil
            origins[key] = origin
          }
          draft.origins = origins
        }
      } footer: {
        Text("Existing scanned values keep their scan source when you correct them. Changing a value clears any previous tape verification.")
      }

      Section {
        Text("Chest: pit to pit. Shoulders: seam to seam. Length: high shoulder point to bottom hem. Waist is optional; only use it for a body check when measured at the corresponding navel level.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle(purpose.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }
          .fontWeight(.semibold)
      }
    }
    .alert("Unable to save", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Check your measurements and try again.")
    }
    .sheet(isPresented: $showScanner) {
      NavigationStack {
        GarmentScanView { key, meters in applyScan(key: key, meters: meters) }
      }
    }
  }

  private func save() {
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    chestValid = chestValid && valid(draft.chestFlat)
    shoulderValid = shoulderValid && valid(draft.shoulderWidth)
    lengthValid = lengthValid && valid(draft.length)
    waistValid = waistValid && (draft.waistFlat == 0 || valid(draft.waistFlat))
    guard !name.isEmpty, chestValid, shoulderValid, lengthValid, waistValid else {
      errorMessage = "Add a name and positive chest, shoulder, and length measurements. Correct any highlighted fields."
      return
    }
    draft.name = name
    draft.category = .tshirt
    do {
      try onSave(draft)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func valid(_ value: Double) -> Bool { value.isFinite && value > 0 }

  private func markEdited(_ key: MeasurementKey) {
    var origins = draft.origins ?? [:]
    var origin = origins[key.rawValue] ?? MeasurementOrigin(source: MeasurementSource(rawValue: sourceRaw) ?? .manual)
    if origins[key.rawValue] != nil { origin.wasEdited = true }
    origin.verifiedWithTape = false
    origin.observedErrorMeters = nil
    origins[key.rawValue] = origin
    draft.origins = origins
  }

  private func applyScan(key: MeasurementKey, meters: Double) {
    guard valid(meters) else { return }
    switch key {
    case .garmentChestFlat:
      draft.chestFlat = meters
      chestValid = true
    case .garmentShoulderWidth:
      draft.shoulderWidth = meters
      shoulderValid = true
    case .garmentLength:
      draft.length = meters
      lengthValid = true
    case .garmentWaistFlat:
      draft.waistFlat = meters
      waistValid = true
    default:
      return
    }
    var origins = draft.origins ?? [:]
    origins[key.rawValue] = MeasurementOrigin(source: .garmentScan)
    draft.origins = origins
  }
}
