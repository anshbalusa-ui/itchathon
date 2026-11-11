import SwiftUI

struct BodyScanCameraView<Camera: View>: View {
  var status: BodyScanCameraStatus
  var startedAt: Date?
  var position: (Date) -> ScanPositionFeedback = { _ in ScanPositionFeedback() }
  var torsoViews = 0
  var legViews = 0
  var close: () -> Void
  var performAction: () -> Void
  var reframe: () -> Void = {}
  var pauseForCancel: (Bool) -> Void = { _ in }
  @ViewBuilder var camera: () -> Camera
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @State private var cancelExpanded = false
  @State private var showingHelp = false
  @State private var panelHeight: CGFloat = 150
  @Namespace private var closeTransition
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        camera()
          .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
          .overlay {
            if status.mode == .framing { BodyScanFloorGuide().allowsHitTesting(false).accessibilityHidden(true) }
          }
          .overlay(alignment: .top) { header.padding(16) }
          .clipped()
        ScrollView {
          VStack(spacing: 12) {
            if status.awaitsNextStep {
              Text(status.title).font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("scan.camera.title")
            }
            Text(status.instruction)
              .font(.callout.weight(.medium)).multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("scan.camera.guidance")
            if status.mode != .initializing && status.mode != .finishing && !status.awaitsNextStep {
              TimelineView(.periodic(from: .now, by: 1)) { context in
                ScanPositionIndicator(position: position(context.date), active: !cancelExpanded && !showingHelp)
              }
            }
            actionRow.disabled(cancelExpanded)
          }
          .padding(20).frame(maxWidth: .infinity)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
        }
        .frame(height: min(panelHeight, geometry.size.height * 0.44))
        .scrollBounceBehavior(.basedOnSize)
        .background(.regularMaterial)
      }
    }
    .background(.black).tint(.blue).preferredColorScheme(.dark)
    .onChange(of: cancelExpanded || showingHelp) { _, value in pauseForCancel(value) }
    .sheet(isPresented: $showingHelp) { help }
  }

  private var header: some View {
    HStack(alignment: .top) {
      Menu {
        Button("Scan help", systemImage: "info") { showingHelp = true }
        Toggle("Guidance haptics", isOn: $haptics)
      } label: {
        Label("Scan options", systemImage: "ellipsis").labelStyle(.iconOnly)
          .frame(width: 44, height: 44)
          .glassEffect(.regular.interactive(), in: .circle)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("scan.options")
      Spacer()
      GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
          if cancelExpanded {
            Button("Keep scanning", systemImage: "checkmark") { setCancelExpanded(false) }
              .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle)
              .accessibilityIdentifier("scan.keep")
          }
          Button {
            if cancelExpanded { close() } else { setCancelExpanded(true) }
          } label: {
            HStack {
              if cancelExpanded { Text("Cancel scan").font(.subheadline.weight(.semibold)) }
              else { Image(systemName: "xmark") }
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, cancelExpanded ? 14 : 0)
            .glassEffect(.regular.interactive(), in: .capsule)
          }
          .buttonStyle(.plain)
          .glassEffectID("close", in: closeTransition)
          .glassEffectTransition(.matchedGeometry)
          .accessibilityLabel(cancelExpanded ? "Cancel scan" : "Close scan")
          .accessibilityHint(cancelExpanded ? "Discards this attempt. Your saved avatar is kept." : "Shows Cancel scan and Keep scanning.")
          .accessibilityIdentifier(cancelExpanded ? "scan.cancel" : "scan.close")
        }
      }
    }
    .foregroundStyle(.white)
  }

  private func setCancelExpanded(_ value: Bool) {
    withAnimation(reduceMotion ? nil : .snappy) { cancelExpanded = value }
  }

  @ViewBuilder private var actionRow: some View {
    if status.pendingAction != nil {
      BodyScanPrimaryButton(title: status.pendingTitle, busy: true, action: {})
    } else if status.action != nil {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) { reframeButton; primaryAction }
        VStack(spacing: 12) { primaryAction; reframeButton }
      }
    } else if status.mode == .initializing || status.mode == .finishing {
      ProgressView().accessibilityLabel(status.title)
    } else {
      HStack(spacing: 8) {
        Circle().fill(.red).frame(width: 8, height: 8).accessibilityHidden(true)
        Text(status.progressTitle)
          .font(.caption.monospacedDigit())
      }
      .accessibilityElement(children: .combine).accessibilityIdentifier("scan.capture-progress")
    }
  }

  private var primaryAction: some View {
    BodyScanPrimaryButton(title: status.actionTitle, enabled: status.actionEnabled, action: performAction)
      .accessibilityIdentifier("scan.camera.action")
  }

  @ViewBuilder private var reframeButton: some View {
    if status.mode == .selecting {
      Button("Reframe", systemImage: "arrow.counterclockwise", action: reframe)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.large)
        .accessibilityHint("Clears the selected box so you can select the whole person again.")
        .accessibilityIdentifier("scan.reframe")
    }
  }

  private var help: some View {
    NavigationStack {
      List {
        Section("Framing") {
          Text("Step back until the head and feet are visible. Keep the person still, with their arms slightly apart.")
          Text("Point the center of the camera at the floor beside their feet and tap Set floor. Then lift the camera and drag the box corners to include their head, hands, and feet. Use Reframe if the box selects the wrong area.")
        }
        Section("Scanning") {
          Text("Tap Start scan. Walk slowly around the person and follow the camera ring. We pause after each circle.")
          Text("The camera needs three photos that clearly show the head, torso, and both ankles, as well as two complete circles and at least 60 photos.")
        }
        Section("This attempt") {
          if let startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              LabeledContent("Time", value: BodyScanTiming.elapsed(since: startedAt, now: context.date))
            }
          }
          LabeledContent("Photos", value: "\(status.shots)")
          LabeledContent("Circles completed", value: "\(status.completedPasses)")
          LabeledContent("Whole-body views checked", value: "\(status.fullBodyViews)")
          LabeledContent("Torso visible in sampled photos", value: "\(torsoViews)")
          LabeledContent("Legs visible in sampled photos", value: "\(legViews)")
          Text("Visibility checks do not measure complete surface coverage. Follow the camera ring.").font(.footnote)
        }
        Section("Distance") {
          Text("When available, the number is depth from the last captured photo, not a live distance. Move closer or back when the camera asks.")
        }
      }
      .navigationTitle("Scan help").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHelp = false } } }
    }
    .presentationDetents([.medium, .large])
  }
}
