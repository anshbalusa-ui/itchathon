import SwiftUI

struct GarmentEntryView: View {
  enum Purpose {
    case favorite
    case candidate

    var title: String { self == .favorite ? "My Fit" : "Check a Garment" }
    var saveTitle: String { self == .favorite ? "Save Favorite" : "Save Garment" }
  }

  @Environment(\.dismiss) private var dismiss
  @AppStorage("fitcheck.preferredUnit") private var unitRaw = EntryUnit.centimeters.rawValue

  var purpose: Purpose
  var onSave: (GarmentProfile) throws -> Void

  @State private var draft: GarmentProfile
  @State private var chestValid = true
  @State private var shoulderValid = true
  @State private var lengthValid = true
  @State private var waistValid = true
  @State private var errorMessage: String?

  init(purpose: Purpose, initial: GarmentProfile = GarmentProfile(), onSave: @escaping (GarmentProfile) throws -> Void) {
    self.purpose = purpose
    self.onSave = onSave
    var copy = initial
    if copy.name == "Scanned garment" { copy.name = "" }
    _draft = State(initialValue: copy)
  }

  private var unit: EntryUnit { EntryUnit(rawValue: unitRaw) ?? .centimeters }

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
          ForEach(EntryUnit.allCases) { option in
            Text(option == .centimeters ? "Centimeters" : "Inches")
              .tag(option.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } footer: {
        Text("Measure the shirt laid flat without stretching it. Use the same method for both shirts.")
      }

      Section("Shirt measurements") {
        MeasurementField(title: "Chest width", meters: $draft.chestFlat, unit: unit, isValid: $chestValid)
        MeasurementField(title: "Shoulders", meters: $draft.shoulderWidth, unit: unit, isValid: $shoulderValid)
        MeasurementField(title: "Length", meters: $draft.length, unit: unit, isValid: $lengthValid)
        MeasurementField(title: "Waist width", meters: $draft.waistFlat, unit: unit, required: false, isValid: $waistValid)
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
}
