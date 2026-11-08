import SwiftUI

struct BodyScanCameraView<Camera: View>: View {
  var status: BodyScanCameraStatus
  var startedAt: Date?
  var close: () -> Void
  var performAction: () -> Void
  @ViewBuilder var camera: () -> Camera
  @State private var informationHeight: CGFloat = 220
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        VStack(spacing: 18) {
          HStack {
            Button("Close scan", systemImage: "xmark", action: close)
              .labelStyle(.iconOnly)
              .buttonStyle(.bordered)
              .buttonBorderShape(.circle)
              .accessibilityIdentifier("scan.close")
            Spacer()
            Text("Body scan").font(.headline).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
          }
          BodyScanJourneyView(step: status.step)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)

        camera()
          .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
          .clipped()

        VStack(spacing: 0) {
          ScrollView {
            information
              .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 8)
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { informationHeight = $0 }
          }
          .frame(height: min(informationHeight, max(100, geometry.size.height * (typeSize.isAccessibilitySize ? 0.24 : 0.36))))
          .scrollBounceBehavior(.basedOnSize)
          if status.mode == .capturing && !status.awaitsNextStep {
            captureProgress.padding(.horizontal, 22).padding(.top, 10)
          }
          actionRow
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 18)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
      }
    }
    .background(.black)
    .tint(.blue)
    .preferredColorScheme(.dark)
  }

  private var information: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(status.title)
          .font(.title2.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("scan.camera.title")
        Text(status.instruction)
          .font(.callout)
          .foregroundStyle(status.issue != nil && !status.awaitsNextStep ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("scan.camera.guidance")
      }
    }
  }

  private var captureProgress: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(status.progressTitle).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text(status.progressDetail).fixedSize(horizontal: false, vertical: true)
      if !status.awaitsNextStep { elapsedLabel.fixedSize(horizontal: false, vertical: true) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .font(.caption).foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("scan.capture-progress")
  }

  @ViewBuilder private var elapsedLabel: some View {
    if let startedAt {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        Text(BodyScanTiming.elapsed(since: startedAt, now: context.date))
      }
    }
  }

  @ViewBuilder private var actionRow: some View {
    if status.pendingAction != nil {
      BodyScanPrimaryButton(title: status.pendingTitle, busy: true, action: {})
    } else if status.action != nil {
      BodyScanPrimaryButton(title: status.actionTitle, enabled: status.actionEnabled, action: performAction)
        .accessibilityIdentifier("scan.camera.action")
    } else {
      HStack(spacing: 10) {
        if status.mode == .initializing || status.mode == .finishing { ProgressView() }
        else { Image(systemName: status.issue == nil ? "camera" : "hand.raised") }
        Text(status.mode == .capturing ? (status.issue == nil ? "Capturing automatically" : "Adjust position to continue") : "Keep On You open")
          .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 40)
    }
  }
}
