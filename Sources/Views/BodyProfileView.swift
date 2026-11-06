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
  @State private var showingBodyScan = false
  @State private var errorMessage: String?

  private var unit: LengthUnit { LengthUnit(rawValue: unitRaw) ?? .centimeters }

  var body: some View {
    Form {
      Section {
        Button {
          showingBodyScan = true
        } label: {
          Label("Scan Body", systemImage: "viewfinder")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Scan estimates waist circumference and records shoulder width and torso length only. Use a tape for chest circumference; width alone cannot determine circumference. Results stay unsaved until you save this form.")
      } footer: {
        Text("Scan estimates waist circumference and records shoulder width and torso length only. Use a tape to measure chest circumference; width alone is not enough to determine circumference. Scan images are not stored.")
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
        Text("Units only change how measurements appear. Saved values keep their precision.")
      }

      Section("Upper body") {
        MeasurementField(title: "Chest circumference", meters: $draft.chestCircumference, unit: unit, isValid: $chestValid) {
          markEdited(.chestCircumference)
        }
        sourceLabel(.chestCircumference)
        MeasurementField(title: "Shoulder width", meters: $draft.shoulderWidth, unit: unit, isValid: $shoulderValid) {
          markEdited(.shoulderWidth)
        }
        sourceLabel(.shoulderWidth)
        MeasurementField(title: "Torso length", meters: $draft.torsoLength, unit: unit, isValid: $torsoValid) {
          markEdited(.torsoLength)
        }
        sourceLabel(.torsoLength)
      }

      Section {
        MeasurementField(title: "Waist circumference", meters: $draft.waistCircumference, unit: unit, isValid: $waistValid) {
          markEdited(.waistCircumference)
        }
        sourceLabel(.waistCircumference)
        MeasurementField(title: "Hip circumference", meters: $draft.hipCircumference, unit: unit, required: false, isValid: $hipValid) {
          markEdited(.hipCircumference)
        }
        sourceLabel(.hipCircumference)
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
    .sheet(isPresented: $showingBodyScan) {
      NavigationStack {
        BodyScanView(onComplete: applyScan, onCancel: cancelBodyScan)
          .navigationTitle("Scan Body")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel", action: cancelBodyScan)
            }
          }
      }
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

  private func cancelBodyScan() {
    showingBodyScan = false
  }

  private func valid(_ value: Double) -> Bool { value.isFinite && value > 0 }

  private func applyScan(_ scanned: BodyProfile) {
    draft.waistCircumference = scanned.waistCircumference
    draft.shoulderWidth = scanned.shoulderWidth
    draft.torsoLength = scanned.torsoLength

    var origins = draft.origins ?? [:]
    for key in [
      MeasurementKey.waistCircumference,
      .shoulderWidth,
      .torsoLength
    ] {
      origins[key.rawValue] = scanned.origins?[key.rawValue] ?? MeasurementOrigin(source: .bodyScan)
    }
    draft.origins = origins

    waistValid = valid(scanned.waistCircumference)
    shoulderValid = valid(scanned.shoulderWidth)
    torsoValid = valid(scanned.torsoLength)
    showingBodyScan = false
  }

  @ViewBuilder
  private func sourceLabel(_ key: MeasurementKey) -> some View {
    let origin = draft.origins?[key.rawValue]
    let title: String = {
      guard let origin else { return "Manual entry" }
      if origin.source == .manual && origin.wasEdited { return "Manually edited" }
      if origin.wasEdited { return "Edited after \(origin.source == .bodyScan ? "scan" : "entry")" }
      switch origin.source {
      case .manual: return "Manual entry"
      case .bodyScan: return "Body scan"
      case .external: return "Imported measurement"
      case .garmentScan: return "Garment scan"
      case .retailer: return "Retailer measurement"
      }
    }()
    Label(title, systemImage: origin?.source == .bodyScan && origin?.wasEdited != true ? "viewfinder" : "pencil")
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityLabel("\(key.displayName), \(title)")
  }

  private func markEdited(_ key: MeasurementKey) {
    var origins = draft.origins ?? [:]
    let existingOrigin = origins[key.rawValue]
    var origin = existingOrigin ?? MeasurementOrigin(source: .manual)
    if existingOrigin != nil { origin.wasEdited = true }
    if origin.source == .bodyScan {
      origin.source = .manual
      origin.wasEdited = true
    }
    origin.verifiedWithTape = false
    origin.observedErrorMeters = nil
    origins[key.rawValue] = origin
    draft.origins = origins
  }
}
