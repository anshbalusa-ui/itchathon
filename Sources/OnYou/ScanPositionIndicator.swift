import SwiftUI

struct ScanPositionIndicator: View {
  var position: ScanPositionFeedback
  var active = true
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @State private var pulse = 0
  @Environment(\.dynamicTypeSize) private var typeSize

  private var color: Color {
    position.direction == .searching ? .secondary : Color(hue: position.quality * 0.33, saturation: 0.6 + position.quality * 0.35, brightness: 0.95)
  }

  var body: some View {
    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    return layout {
      Image(systemName: position.direction.symbol).font(.title3.weight(.semibold))
        .frame(width: 28).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(position.direction.instruction).font(.subheadline.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
        Text(position.source).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .layoutPriority(1)
      Spacer(minLength: 4)
      Text(position.distanceText).font(.title3.monospacedDigit().weight(.semibold))
        .accessibilityLabel("Distance").accessibilityValue(position.distanceText)
      Button(haptics ? "Turn guidance haptics off" : "Turn guidance haptics on", systemImage: "waveform") { haptics.toggle() }
        .labelStyle(.iconOnly).buttonStyle(.plain).frame(minWidth: 44, minHeight: 44)
        .foregroundStyle(haptics ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
    }
    .foregroundStyle(color)
    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("scan.position")
    .task(id: active && haptics) {
      guard active && haptics else { return }
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
        pulse += 1
      }
    }
    .sensoryFeedback(trigger: pulse) { _, _ in
      active && haptics && position.intensity > 0 ? .impact(weight: .light, intensity: position.intensity) : nil
    }
    .sensoryFeedback(.alignment, trigger: position.direction) { old, new in active && haptics && old != .hold && new == .hold }
  }
}
