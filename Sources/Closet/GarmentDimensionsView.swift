import SwiftUI

struct GarmentDimensionsView: View {
  var dimensions: GarmentScanDimensions
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    row("Body width", meters: dimensions.bodyWidthM, id: "width")
    row("Length", meters: dimensions.lengthM, id: "length")
    row("Sleeve span", meters: dimensions.sleeveSpanM, id: "sleeves")
  }

  private func row(_ title: String, meters: Double, id: String) -> some View {
    let value = centimeters(meters)
    return Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
          Text(value).foregroundStyle(.secondary)
        }
      } else { LabeledContent(title, value: value) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(value)
    .accessibilityIdentifier("garment.dimensions.\(id)")
  }

  private func centimeters(_ meters: Double) -> String {
    Foundation.Measurement(value: meters * 100, unit: UnitLength.centimeters)
      .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                              numberFormatStyle: .number.precision(.fractionLength(0...1))))
  }
}
