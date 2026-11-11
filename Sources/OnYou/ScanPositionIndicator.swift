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
    return Group {
      if position.meters != nil {
        layout {
          Image(systemName: position.direction == .hold || position.direction == .searching ? "ruler" : position.direction.symbol)
            .accessibilityHidden(true)
          Text(position.distanceText).font(.subheadline.monospacedDigit().weight(.semibold))
          Text(position.source).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Distance, \(position.distanceText). \(position.source). \(position.direction.instruction)")
        .accessibilityIdentifier("scan.position")
      }
    }
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
