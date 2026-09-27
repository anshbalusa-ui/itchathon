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
                            Text("\(closest.report.score)")
                                .font(.title.bold().monospacedDigit())
                        }

                        Text(closest.summary)
                            .font(.headline)

                        Text("This is the highest measurement-based fit score among the available sizes, not a guarantee of personal preference.")
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
                            Text("\(size.report.score)")
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
                                Text(dimension.band.rawValue)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                Text("Scores compare your saved measurements with the actual measurements supplied for each garment size. Fabric stretch, cut, construction, and personal preference can change how a size feels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Compare Sizes")
    }
}
