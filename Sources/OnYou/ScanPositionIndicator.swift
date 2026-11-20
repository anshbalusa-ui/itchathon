import SwiftUI

struct ScanPositionIndicator: View {
  var position: ScanPositionFeedback
  var active = true
  @Environment(\.dynamicTypeSize) private var typeSize

  private var color: Color {
    position.direction == .searching ? .secondary : Color(hue: position.quality * 0.33, saturation: 0.8, brightness: 0.95)
  }

  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    return layout {
      Image(systemName: position.direction.symbol).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(position.direction.instruction).font(.subheadline.weight(.semibold))
        HStack(spacing: 6) {
          Text("Distance \(position.distanceText)").font(.caption.monospacedDigit())
          Text(position.source).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .foregroundStyle(color)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(position.direction.instruction). Distance \(position.distanceText). \(position.source)")
    .accessibilityIdentifier("scan.position")
    .accessibilityHidden(!active)
  }
}
