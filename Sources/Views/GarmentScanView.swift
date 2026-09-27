import SwiftUI

struct GarmentScanView: View {
    @EnvironmentObject private var store: ProfileStore
    @State private var status = "Lay the garment flat and measure one dimension at a time."
    @State private var selectedField: GarmentField = .chest

    enum GarmentField: String, CaseIterable, Identifiable {
        case chest = "Chest width"
        case shoulders = "Shoulder width"
        case waist = "Waist width"
        case length = "Length"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            ARMeasurementView(
                onMeasurement: assign,
                onStatus: { status = $0 }
            )
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 14) {
                Picker("Measurement", selection: $selectedField) {
                    ForEach(GarmentField.allCases) { field in
                        Text(field.rawValue).tag(field)
                    }
                }
                .pickerStyle(.menu)

                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Check fit") {
                    store.evaluateCurrentGarment()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.currentGarment.isUsable)

                if let report = store.lastReport {
                    NavigationLink("View \(report.score) Fit Score") {
                        FitResultView(report: report)
                    }
                    .font(.headline)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Measure Garment")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func assign(_ meters: Double) {
        switch selectedField {
        case .chest:
            store.currentGarment.chestFlat = meters
        case .shoulders:
            store.currentGarment.shoulderWidth = meters
        case .waist:
            store.currentGarment.waistFlat = meters
        case .length:
            store.currentGarment.length = meters
        }

        status = String(format: "%@ saved: %.1f cm", selectedField.rawValue, meters * 100)
    }
}
