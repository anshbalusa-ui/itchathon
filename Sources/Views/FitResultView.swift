import SwiftUI

struct FitResultView: View {
    let report: FitReport

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("\(report.score)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                    Text("Fit Score")
                        .font(.headline)
                    Text(report.band.rawValue)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            Section("Why") {
                ForEach(report.dimensions) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(result.label)
                                .font(.headline)
                            Spacer()
                            Text("\(result.score)")
                                .font(.headline.monospacedDigit())
                        }

                        Text(result.band.rawValue)
                            .font(.subheadline)

                        Text(easeDescription(result.easeMeters))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Text("Prototype estimate only. Fabric stretch, construction, and personal preference can change how a garment feels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Fit Result")
    }

    private func easeDescription(_ meters: Double) -> String {
        let cm = meters * 100
        if cm >= 0 {
            return String(format: "%.1f cm of room compared with your saved measurement.", cm)
        }
        return String(format: "%.1f cm smaller than your saved measurement.", abs(cm))
    }
}
