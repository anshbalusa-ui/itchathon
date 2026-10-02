import SwiftUI

struct SizeComparisonView: View {
  var comparison: SizeComparisonReport
  @State private var reference: ScoreReference = .body

  private enum ScoreReference: String, CaseIterable, Identifiable {
    case body
    case favorite

    var id: String { rawValue }
    var title: String { self == .body ? "Body" : "Favorite" }
  }

  private var recommendedIDs: [UUID] {
    reference == .body ? comparison.recommendedBodyIDs : comparison.recommendedIDs
  }

  private var recommendedLabels: [String] {
    comparison.sizes.filter { recommendedIDs.contains($0.id) }.map(\.sizeLabel)
  }

  var body: some View {
    List {
      Section {
        Picker("Compare to", selection: $reference) {
          ForEach(ScoreReference.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.segmented)
      }

      Section("Closest sizes") {
        Text(recommendedLabels.isEmpty ? "No recommended sizes" : recommendedLabels.joined(separator: ", "))
          .font(.headline)
      }

      Section("Each size") {
        ForEach(comparison.sizes) { size in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(size.sizeLabel.isEmpty ? "Unnamed size" : size.sizeLabel)
                .font(.headline)
              Spacer()
              if recommendedIDs.contains(size.id) {
                Text("Closest")
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.tint)
              }
            }
            if let report = size.report {
              Text(physicalDescription(report.physical))
                .font(.subheadline)
                .foregroundStyle(.secondary)
              let dimensions = reference == .body ? report.bodyDimensions : report.dimensions
              ForEach(dimensions) { dimension in
                HStack {
                  Text(dimensionTitle(dimension.id))
                  Spacer()
                  Text(signedScore(dimension.signedScore))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                  Text(signedCentimeters(dimension.deltaMeters))
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
                .accessibilityValue("\(signedScore(dimension.signedScore)) relative to \(reference.title)")
              }
            } else {
              Text(size.issue ?? "Measurements incomplete")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 5)
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Compare Sizes")
    .navigationBarTitleDisplayMode(.inline)
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
    case .passesMeasuredChecks: return "Passes body checks"
    case .needsVerification: return "Verify measurements"
    case .smallerThanBody: return "Below body measurement"
    }
  }

  private func signedScore(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

  private func signedCentimeters(_ meters: Double) -> String {
    let amount = (abs(meters) * 100).formatted(.number.precision(.fractionLength(1)))
    let prefix = meters > 0 ? "+" : meters < 0 ? "−" : ""
    return "\(prefix)\(amount) cm"
  }
}
