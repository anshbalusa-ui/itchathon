import SwiftUI

struct FitResultView: View {
  var report: FitReport
  @State private var reference: ScoreReference = .body

  private enum ScoreReference: String, CaseIterable, Identifiable {
    case body
    case favorite

    var id: String { rawValue }
    var title: String { self == .body ? "Body" : "Favorite" }
  }

  private var dimensions: [FitDimensionResult] {
    reference == .body ? report.bodyDimensions : report.dimensions
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

      Section {
        ForEach(dimensions) { dimension in
          HStack {
            Text(dimensionTitle(dimension.id))
              .font(.headline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
              Text(signedScore(dimension.signedScore))
                .font(.title3.bold().monospacedDigit())
              Text(signedCentimeters(dimension.deltaMeters))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(dimensionTitle(dimension.id)) score")
          .accessibilityValue("\(signedScore(dimension.signedScore)) relative to \(reference.title)")
          .accessibilityIdentifier(dimension.id == .chest ? "chest-score" : "\(dimension.id.rawValue)-score")
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Results")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func dimensionTitle(_ dimension: FitDimension) -> String {
    switch dimension {
    case .chest: return "Chest"
    case .shoulders: return "Shoulders"
    case .length: return "Length"
    }
  }

  private func signedScore(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

  private func signedCentimeters(_ meters: Double) -> String {
    let amount = (abs(meters) * 100).formatted(.number.precision(.fractionLength(1)))
    let prefix = meters > 0 ? "+" : meters < 0 ? "−" : ""
    return "\(prefix)\(amount) cm"
  }
}
