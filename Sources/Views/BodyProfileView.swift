import SwiftUI

struct BodyProfileView: View {
  @EnvironmentObject private var store: ProfileStore
  @Environment(\.dismiss) private var dismiss
  @AppStorage("fitcheck.preferredUnit") private var unitRaw = LengthUnit.centimeters.rawValue

  @State private var draft = BodyProfile()
  @State private var didLoad = false
  @State private var chestValid = true
  @State private var waistValid = true
  @State private var shoulderValid = true
  @State private var torsoValid = true
  @State private var hipValid = true
  @State private var showValidation = false
  @State private var errorMessage: String?

  private var unit: LengthUnit { LengthUnit(rawValue: unitRaw) ?? .centimeters }

  var body: some View {
    Form {
      Section {
        Picker("Units", selection: $unitRaw) {
          ForEach(LengthUnit.allCases) { option in
            Text(option == .centimeters ? "Centimeters" : "Inches")
              .tag(option.rawValue)
          }
        }
        .pickerStyle(.segmented)
      } footer: {
        Text("Units only change how measurements appear. Saved values keep their precision.")
      }

      Section("Upper body") {
        MeasurementField(title: "Chest circumference", meters: $draft.chestCircumference, unit: unit, isValid: $chestValid) {
          markEdited(.chestCircumference)
        }
        MeasurementField(title: "Shoulder width", meters: $draft.shoulderWidth, unit: unit, isValid: $shoulderValid) {
          markEdited(.shoulderWidth)
        }
        MeasurementField(title: "Torso length", meters: $draft.torsoLength, unit: unit, isValid: $torsoValid) {
          markEdited(.torsoLength)
        }
      }

      Section {
        MeasurementField(title: "Waist circumference", meters: $draft.waistCircumference, unit: unit, isValid: $waistValid) {
          markEdited(.waistCircumference)
        }
        MeasurementField(title: "Hip circumference", meters: $draft.hipCircumference, unit: unit, required: false, isValid: $hipValid) {
          markEdited(.hipCircumference)
        }
      } header: {
        Text("Additional measurements")
      } footer: {
        Text("Measure waist at navel level. Hip is optional and is not used for T-shirt fit checks.")
      }

      Section {
        Label("Measurements stay on this iPhone.", systemImage: "lock.shield")
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("My Body")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") { save() }
          .fontWeight(.semibold)
      }
    }
    .alert("Check measurements", isPresented: $showValidation) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "Enter positive values for chest, waist, shoulders, and torso. Correct any highlighted fields before saving.")
    }
    .onAppear {
      guard !didLoad else { return }
      didLoad = true
      draft = store.bodyProfile
    }
  }

  private func save() {
    chestValid = chestValid && valid(draft.chestCircumference)
    waistValid = waistValid && valid(draft.waistCircumference)
    shoulderValid = shoulderValid && valid(draft.shoulderWidth)
    torsoValid = torsoValid && valid(draft.torsoLength)
    hipValid = hipValid && (draft.hipCircumference == 0 || valid(draft.hipCircumference))
    guard chestValid && waistValid && shoulderValid && torsoValid && hipValid else {
      showValidation = true
      return
    }
    do {
      try store.saveBody(draft)
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
      showValidation = true
    }
  }

  private func valid(_ value: Double) -> Bool { value.isFinite && value > 0 }

  private func markEdited(_ key: MeasurementKey) {
    var origins = draft.origins ?? [:]
    var origin = origins[key.rawValue] ?? MeasurementOrigin(source: .manual)
    if origins[key.rawValue] != nil { origin.wasEdited = true }
    origin.verifiedWithTape = false
    origin.observedErrorMeters = nil
    origins[key.rawValue] = origin
    draft.origins = origins
  }
}
