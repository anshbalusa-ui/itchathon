import SwiftUI

struct SizeComparisonView: View {
    let comparison: SizeComparisonReport

    var body: some View {
        List {
            if let closest = comparison.closestMatch {
                Section("Closest match") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(closest.sizeLabel)
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                            Spacer()
                            Text(formattedScore(closest.report.score))
                                .font(.title.bold().monospacedDigit())
                        }

                        Text(closest.summary)
                            .font(.headline)

                        Text("Closest to 0 among the available sizes. Negative means too small; positive means too large.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }

            Section("How each size would fit") {
                ForEach(comparison.sizes) { size in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(size.sizeLabel)
                                .font(.title3.bold())
                            Spacer()
                            Text(formattedScore(size.report.score))
                                .font(.title3.bold().monospacedDigit())
                            Text("Fit")
                                .foregroundStyle(.secondary)
                        }

                        Text(size.summary)
                            .font(.subheadline)

                        ForEach(size.report.dimensions) { dimension in
                            HStack {
                                Text(dimension.label)
                                Spacer()
                                Text("\(formattedScore(dimension.score)) · \(dimension.band.rawValue)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                Text("-100 = too small · 0 = ideal · +100 = too large")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Scores use the actual measurements supplied for each garment size. Fabric stretch, cut, construction, and personal preference can change how a size feels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Compare Sizes")
    }

    private func formattedScore(_ score: Int) -> String {
        score > 0 ? "+\(score)" : "\(score)"
    }
}
