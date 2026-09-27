import SwiftUI

struct BodyProfileView: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("For the MVP, measurements can be entered or corrected manually. The guided camera scan can write into these same fields.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Upper body") {
                CentimeterField(title: "Chest circumference", meters: $store.bodyProfile.chestCircumference)
                CentimeterField(title: "Shoulder width", meters: $store.bodyProfile.shoulderWidth)
                CentimeterField(title: "Torso length", meters: $store.bodyProfile.torsoLength)
            }

            Section("Additional fit") {
                CentimeterField(title: "Waist circumference", meters: $store.bodyProfile.waistCircumference)
                CentimeterField(title: "Hip circumference", meters: $store.bodyProfile.hipCircumference)
            }

            Button("Save profile") {
                store.saveBodyProfile()
                dismiss()
            }
            .disabled(!store.bodyProfile.isUsable)
        }
        .navigationTitle("Your Fit Profile")
    }
}

private struct CentimeterField: View {
    let title: String
    @Binding var meters: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("cm", value: Binding(
                get: { meters * 100 },
                set: { meters = $0 / 100 }
            ), format: .number.precision(.fractionLength(0...1)))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)

            Text("cm")
                .foregroundStyle(.secondary)
        }
    }
}
