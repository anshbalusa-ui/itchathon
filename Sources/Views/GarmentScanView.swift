import SwiftUI

struct GarmentScanView: View {
  @Environment(\.dismiss) private var dismiss

  var onSave: (MeasurementKey, Double) -> Void

  @State private var selectedField: GarmentDimension = .chest
  @State private var pendingMeasurement: Double?
  @State private var status = "Lay the shirt flat. Aim the center reticle at point A, then tap."
  @State private var resetToken = UUID()

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .top) {
        ARMeasurementView(
          onMeasurement: { meters in
            guard meters.isFinite, meters > 0, pendingMeasurement == nil else { return }
            pendingMeasurement = meters
          },
          onStatus: { status = $0 }
        )
        .id(resetToken)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if pendingMeasurement != nil {
          Color.clear
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }

        Text(selectedField.instruction)
          .font(.footnote.weight(.medium))
          .multilineTextAlignment(.center)
          .padding(.horizontal, 14)
          .padding(.vertical, 9)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          .padding()
          .allowsHitTesting(false)
      }

      VStack(alignment: .leading, spacing: 12) {
        Picker("Dimension", selection: $selectedField) {
          ForEach(GarmentDimension.allCases) { field in
            Text(field.title).tag(field)
          }
        }
        .pickerStyle(.menu)
        .onChange(of: selectedField) { _, _ in reset() }

        Text(status)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let pendingMeasurement {
          Text("A to B · \((pendingMeasurement * 100).formatted(.number.precision(.fractionLength(1)))) cm")
            .font(.title3.bold().monospacedDigit())
            .accessibilityLabel("Pending \(selectedField.title) measurement, \((pendingMeasurement * 100).formatted(.number.precision(.fractionLength(1)))) centimeters")
        }

        HStack(spacing: 12) {
          Button("Reset", systemImage: "arrow.counterclockwise") { reset() }
            .buttonStyle(.bordered)
          Button("Use Measurement", systemImage: "checkmark") {
            guard let pendingMeasurement else { return }
            onSave(selectedField.key, pendingMeasurement)
            reset()
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .disabled(pendingMeasurement == nil)
        }
        .frame(maxWidth: .infinity)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.regularMaterial)
    }
    .navigationTitle("Measure Shirt")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") { dismiss() }
      }
    }
  }

  private func reset() {
    pendingMeasurement = nil
    resetToken = UUID()
    status = "Aim the center reticle at point A, then tap."
  }
}

private enum GarmentDimension: String, CaseIterable, Identifiable {
  case chest
  case shoulders
  case length
  case waist

  var id: String { rawValue }
  var title: String {
    switch self {
    case .chest: return "Chest width"
    case .shoulders: return "Shoulders"
    case .length: return "Length"
    case .waist: return "Waist width"
    }
  }
  var key: MeasurementKey {
    switch self {
    case .chest: return .garmentChestFlat
    case .shoulders: return .garmentShoulderWidth
    case .length: return .garmentLength
    case .waist: return .garmentWaistFlat
    }
  }
  var instruction: String {
    switch self {
    case .chest: return "Pit to pit · flat and unstretched"
    case .shoulders: return "Seam to seam · straight across"
    case .length: return "High shoulder point to bottom hem"
    case .waist: return "At the navel level, if known"
    }
  }
}
