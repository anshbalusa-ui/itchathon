import SwiftUI

struct BodyScanCameraView<Camera: View>: View {
  var status: BodyScanCameraStatus
  var startedAt: Date?
  var position: (Date) -> ScanPositionFeedback = { _ in ScanPositionFeedback(source: "Waiting for a depth photo") }
  var torsoViews = 0
  var legViews = 0
  var close: () -> Void
  var performAction: () -> Void
  @ViewBuilder var camera: () -> Camera
  @State private var informationHeight: CGFloat = 220
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        camera().frame(maxWidth: .infinity, maxHeight: .infinity)
          .ignoresSafeArea()
        VStack(spacing: 0) {
          HStack {
            Button("Close scan", systemImage: "xmark", action: close)
              .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
              .accessibilityIdentifier("scan.close")
            Spacer()
            Text(status.mode == .capturing ? status.passLabel : "Body scan")
              .font(.subheadline.weight(.semibold))
              .padding(.horizontal, 18).padding(.vertical, 12)
              .glassEffect(in: .capsule)
            Spacer()
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
          }
          Spacer(minLength: 30)
          VStack(spacing: 12) {
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                information
                if !status.awaitsNextStep && status.mode != .finishing {
                  TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScanPositionIndicator(position: position(context.date), active: status.trackingNormal)
                  }
                }
                if status.mode == .capturing { captureProgress }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { informationHeight = $0 }
            }
            .frame(height: min(informationHeight, max(120, geometry.size.height * (typeSize.isAccessibilitySize ? 0.42 : 0.34))))
            .scrollBounceBehavior(.basedOnSize)
            actionRow.fixedSize(horizontal: false, vertical: true)
          }
          .padding(16)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
      }
    }
    .background(.black)
    .tint(.blue)
    .preferredColorScheme(.dark)
  }

  private var information: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        Text(status.title)
          .font(.title3.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
          .accessibilityIdentifier("scan.camera.title")
        Text(status.instruction)
          .font(.callout)
          .foregroundStyle(status.issue != nil && !status.awaitsNextStep ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("scan.camera.guidance")
      }
    }
  }

  private var captureProgress: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("\(status.shots) photos · \(min(2, status.completedPasses)) of 2 circles complete").font(.subheadline.weight(.medium)).foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      if torsoViews + legViews > 0 {
        Text("Sampled photos · Torso visible in \(torsoViews) · Legs visible in \(legViews)")
          .fixedSize(horizontal: false, vertical: true)
        Text("Visibility is not complete surface coverage. Follow the camera ring.")
          .fixedSize(horizontal: false, vertical: true)
      } else if status.awaitsNextStep {
        Text(status.progressDetail).fixedSize(horizontal: false, vertical: true)
      }
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
