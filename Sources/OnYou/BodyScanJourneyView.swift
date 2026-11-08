import SwiftUI

struct BodyScanJourneyView: View {
  var step: BodyScanStep
  @Environment(\.dynamicTypeSize) private var typeSize
  private var steps: [BodyScanStep] { BodyScanStep.allCases.filter { $0 != .ready } }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        ForEach(steps) { item in
          Capsule()
            .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
            .frame(height: 4)
        }
      }
      if typeSize.isAccessibilitySize {
        Text(step == .ready ? "Scan complete" : step.title)
          .font(.headline).fixedSize(horizontal: false, vertical: true)
      } else {
        HStack(spacing: 8) {
          ForEach(steps) { item in
            HStack(spacing: 4) {
              if item.rawValue < step.rawValue {
                Image(systemName: "checkmark").font(.caption2.weight(.bold))
              }
              Text(item.title).font(.caption.weight(item == step ? .semibold : .regular))
            }
            .foregroundStyle(item.rawValue <= step.rawValue ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Scan progress")
    .accessibilityValue(step == .ready ? "All steps complete" : "Current step: \(step.title)")
    .accessibilityIdentifier("scan.journey")
  }
}
