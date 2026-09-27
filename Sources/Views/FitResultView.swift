import SwiftUI

struct FitResultView: View {
  var report: FitReport
  var bodyProfile: BodyProfile
  var preferred: GarmentProfile
  var candidate: GarmentProfile

  var body: some View {
    List {
      Section("Physical check") {
        Label(physicalTitle(report.physical), systemImage: physicalSymbol(report.physical))
          .font(.headline)
        ForEach(report.checks) { check in
          VStack(alignment: .leading, spacing: 4) {
            Text(check.id == MeasurementKey.waistCircumference.rawValue ? "Waist at navel" : "Chest circumference")
              .font(.headline)
            let flatWidthMeters = check.id == MeasurementKey.waistCircumference.rawValue ? candidate.waistFlat : candidate.chestFlat
            Text("Body circumference \(centimeters(check.bodyMeters)) · Shirt flat width \(centimeters(flatWidthMeters)) × 2 = estimated shirt circumference \(centimeters(check.candidateMeters))")
              .font(.subheadline)
              .accessibilityLabel("Body circumference \(centimeters(check.bodyMeters)). Shirt flat width \(centimeters(flatWidthMeters)) times 2 equals estimated shirt circumference \(centimeters(check.candidateMeters)).")
            Text("\(signedCentimeters(check.easeMeters)) room · \(physicalTitle(check.status))")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 3)
        }
        if report.referencePhysical != .passesMeasuredChecks {
          Text("Your favorite shirt also needs a measurement check before its fit can be treated as a verified reference.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      Section {
        ForEach(report.dimensions) { dimension in
          VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
              Text(dimensionTitle(dimension.id))
                .font(.headline)
              Spacer()
              Text(signedScore(dimension.signedScore))
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.tint)
            }
            Text(differenceDescription(dimension))
              .font(.subheadline)
            scoreScale(dimension.signedScore)
              .frame(height: 16)
              .accessibilityHidden(true)
            HStack {
              Text("−100 \(dimension.id == .length ? "Shorter" : "Smaller")")
              Spacer()
              Text("0 Preferred")
              Spacer()
              Text("+100 \(dimension.id == .length ? "Longer" : "Larger")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          .padding(.vertical, 5)
          .accessibilityElement(children: .combine)
          .accessibilityValue("\(signedScore(dimension.signedScore)) relative to \(report.preferredName). \(differenceDescription(dimension))")
        }
      } header: {
        Text("Compared with \(report.preferredName)")
      } footer: {
        Text("Each number is a separate preference comparison. Zero matches your favorite garment's dimension, subject to the physical checks above.")
      }

      Section("Measurement sources") {
        sourceRow("Body chest", origin: bodyProfile.origins?[MeasurementKey.chestCircumference.rawValue])
        sourceRow("Favorite chest", origin: preferred.origins?[MeasurementKey.garmentChestFlat.rawValue])
        sourceRow("Candidate chest", origin: candidate.origins?[MeasurementKey.garmentChestFlat.rawValue])
        sourceRow("Favorite shoulders", origin: preferred.origins?[MeasurementKey.garmentShoulderWidth.rawValue])
        sourceRow("Candidate shoulders", origin: candidate.origins?[MeasurementKey.garmentShoulderWidth.rawValue])
        sourceRow("Favorite length", origin: preferred.origins?[MeasurementKey.garmentLength.rawValue])
        sourceRow("Candidate length", origin: candidate.origins?[MeasurementKey.garmentLength.rawValue])
      }

      Section("What this cannot assess") {
        Text(report.waistAssessed
             ? "Waist is checked only because this shirt's waist was marked at the same navel level as your body measurement."
             : "Waist not assessed: a matching garment waist measurement was not supplied.")
        Text("Shoulder and length scores compare shirts. Body shoulder and torso measurements are not direct garment-fit rules.")
        Text("Stretch, cut, armholes, sleeves, and movement may change how this shirt feels. Near-boundary or unverified measurements need a tape check.")
      }
      .font(.footnote)
      .foregroundStyle(.secondary)
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Results")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func scoreScale(_ score: Int) -> some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Color.secondary.opacity(0.18)).frame(height: 4)
        Rectangle().fill(Color.secondary.opacity(0.55))
          .frame(width: 1, height: 14)
          .position(x: geometry.size.width / 2, y: 8)
        Circle().fill(Color.accentColor)
          .frame(width: 12, height: 12)
          .position(x: geometry.size.width * CGFloat(score + 100) / 200, y: 8)
      }
      .frame(height: 16)
    }
  }

  private func sourceRow(_ title: String, origin: MeasurementOrigin?) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
      Text(sourceDescription(origin))
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
  }

  private func sourceDescription(_ origin: MeasurementOrigin?) -> String {
    guard let origin else { return "Source not recorded" }
    let source: String
    switch origin.source {
    case .manual: source = "Entered manually"
    case .external: source = "External measurement"
    case .retailer: source = "Retailer measurement"
    case .bodyScan: source = "Guided body scan"
    case .garmentScan: source = "Garment camera measurement"
    }
    var details = [source]
    if origin.wasEdited { details.append("edited") }
    if origin.verifiedWithTape {
      details.append("checked with tape")
    } else if origin.source == .bodyScan || origin.source == .garmentScan {
      details.append("not tape-verified")
    }
    if let error = origin.observedErrorMeters {
      details.append("observed error \(centimeters(error)) in local checks")
    }
    return details.joined(separator: " · ")
  }

  private func physicalTitle(_ status: PhysicalStatus) -> String {
    switch status {
    case .passesMeasuredChecks: return "Passes measured body checks"
    case .needsVerification: return "Verify with a tape measure"
    case .smallerThanBody: return "Smaller than measured body"
    }
  }

  private func physicalSymbol(_ status: PhysicalStatus) -> String {
    switch status {
    case .passesMeasuredChecks: return "checkmark.seal"
    case .needsVerification: return "exclamationmark.triangle"
    case .smallerThanBody: return "xmark.octagon"
    }
  }

  private func dimensionTitle(_ dimension: FitDimension) -> String {
    switch dimension {
    case .chest: return "Chest"
    case .shoulders: return "Shoulders"
    case .length: return "Length"
    }
  }

  private func differenceDescription(_ result: FitDimensionResult) -> String {
    let measure = result.id == .chest ? "around the chest" : result.id == .length ? "in length" : "at the shoulders"
    let direction = result.deltaMeters < 0 ? "less" : result.deltaMeters > 0 ? "more" : "difference"
    if abs(result.deltaMeters) < 0.0005 {
      return "Same \(measure) as \(report.preferredName): \(centimeters(result.candidateMeters))."
    }
    return "\(centimeters(abs(result.deltaMeters))) \(direction) \(measure) than \(report.preferredName). Favorite: \(centimeters(result.preferredMeters)); this shirt: \(centimeters(result.candidateMeters))."
  }

  private func signedScore(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

  private func centimeters(_ meters: Double) -> String {
    "\((meters * 100).formatted(.number.precision(.fractionLength(1)))) cm"
  }

  private func signedCentimeters(_ meters: Double) -> String {
    let prefix = meters > 0 ? "+" : ""
    return prefix + centimeters(meters)
  }
}
