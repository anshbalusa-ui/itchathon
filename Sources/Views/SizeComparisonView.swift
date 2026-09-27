import SwiftUI

struct SizeComparisonView: View {
  var comparison: SizeComparisonReport
  var chart: GarmentSizeChart?

  var body: some View {
    List {
      Section("Closest verified sizes") {
        if comparison.recommendedIDs.isEmpty {
          Label("No verified match", systemImage: "exclamationmark.triangle")
            .font(.headline)
          Text("No entered size passes the measured body checks with a verified favorite reference. Review the measurements before choosing a size.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          Text(recommendedLabels.joined(separator: ", "))
            .font(.title2.bold())
          Text("These sizes have the smallest worst dimension difference among those that pass measured checks. Ties stay visible.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }

      Section("Each size") {
        ForEach(comparison.sizes) { size in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(size.sizeLabel.isEmpty ? "Unnamed size" : size.sizeLabel)
                .font(.headline)
              Spacer()
              if comparison.recommendedIDs.contains(size.id) {
                Label("Closest", systemImage: "checkmark.seal")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tint)
              }
            }
            if let report = size.report {
              Text(physicalDescription(report.physical))
                .font(.subheadline)
                .foregroundStyle(.secondary)
              ForEach(report.dimensions) { dimension in
                HStack {
                  Text(dimensionTitle(dimension.id))
                  Spacer()
                  Text(signedScore(dimension.signedScore))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                  Text("(\(signedCentimeters(dimension.deltaMeters)))")
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
              }
              if !report.waistAssessed {
                Text("Waist not assessed")
                  .font(.footnote)
                  .foregroundStyle(.secondary)
              }
            } else {
              Text(size.issue ?? "Measurements incomplete")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 5)
          .accessibilityElement(children: .combine)
        }
      }

      Section("Source and limits") {
        Text(chart?.sourceNote ?? "Chart source not recorded")
        Text("Use finished garment measurements only. A body-size recommendation chart cannot provide actual shirt dimensions.")
        Text("Chest, shoulder, and length numbers compare each size with your favorite. Negative is smaller or shorter; positive is larger or longer. No single score combines them.")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Compare Sizes")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var recommendedLabels: [String] {
    comparison.sizes.filter { comparison.recommendedIDs.contains($0.id) }.map(\.sizeLabel)
  }

  private func dimensionTitle(_ value: FitDimension) -> String {
    switch value {
    case .chest: return "Chest"
    case .shoulders: return "Shoulders"
    case .length: return "Length"
    }
  }

  private func physicalDescription(_ status: PhysicalStatus) -> String {
    switch status {
    case .passesMeasuredChecks: return "Passes measured body checks"
    case .needsVerification: return "Needs tape verification"
    case .smallerThanBody: return "Smaller than measured body"
    }
  }

  private func signedScore(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

  private func signedCentimeters(_ meters: Double) -> String {
    let amount = (abs(meters) * 100).formatted(.number.precision(.fractionLength(1)))
    let prefix = meters > 0 ? "+" : meters < 0 ? "−" : ""
    return "\(prefix)\(amount) cm"
  }
}
