import SwiftUI

struct BodyScanCameraView<Camera: View>: View {
  var status: BodyScanCameraStatus
  var position = ScanPositionFeedback()
  var close: () -> Void
  var performAction: () -> Void
  var paused = false
  var pauseCapture: (Bool) -> Void = { _ in }
  @ViewBuilder var camera: () -> Camera
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @State private var showingHelp = false
  @State private var expiredObservation: TimeInterval?
  @ScaledMetric(relativeTo: .body) private var controlsHeight: CGFloat = 184
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var promptsVisible: Bool { paused || showingHelp }

  private var guidanceActive: Bool {
    !promptsVisible && scenePhase == .active && (status.mode == .framing || status.mode == .capturing)
  }

  private var readyObservation: TimeInterval? {
    status.mode == .framing && status.calibrated && !status.pendingStart ? status.observedAt : nil
  }

  private func instruction(isPortrait: Bool) -> String {
    switch status.mode {
    case .initializing: "Getting the camera ready…"
    case .finishing: "Checking your scan…"
    case .framing, .capturing:
      if !isPortrait { "Hold iPhone upright." }
      else if status.pendingStart { "Starting scan…" }
      else { status.instruction }
    }
  }

  var body: some View {
    GeometryReader { geometry in
      let isPortrait = geometry.size.height > geometry.size.width
      let guidance = instruction(isPortrait: isPortrait)
      let canStart = isPortrait && guidanceActive && status.observedAt != expiredObservation
        && status.canStart(now: ProcessInfo.processInfo.systemUptime)
      let layout = isPortrait ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
      layout {
        camera()
          .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
          .overlay {
            if isPortrait {
              ZStack {
                BodyScanFramingGuide(showOutline: true)
                  .stroke(.white.opacity(0.48), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                  .opacity(status.mode == .framing ? 1 : 0)
                  .accessibilityElement(children: .ignore)
                  .accessibilityLabel("Full-body framing guide")
                  .accessibilityIdentifier("scan.framing-outline")
                  .accessibilityHidden(status.mode != .framing)
                BodyScanFramingGuide(showOutline: false)
                  .stroke(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                  .opacity(status.mode == .capturing ? 1 : 0)
                  .accessibilityHidden(true)
              }
              .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: status.mode)
              .allowsHitTesting(false)
            }
          }
          .overlay { ScanWarningOverlay(position: position, active: isPortrait && guidanceActive) }
          .overlay(alignment: .bottom) {
            if isPortrait && !reduceTransparency {
              LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
          }
          .clipped()
        // Instructions can wrap or scroll without moving the calibrated camera viewport.
        controls(guidance, isPortrait: isPortrait, canStart: canStart)
          .frame(width: isPortrait ? nil : geometry.size.width * 0.44,
                 height: isPortrait ? min(controlsHeight, geometry.size.height / 2) : nil)
          .background(.black)
      }
      .onChange(of: guidance) { _, instruction in
        if !promptsVisible && scenePhase == .active && status.mode != .finishing {
          AccessibilityNotification.Announcement(instruction).post()
        }
      }
      .sensoryFeedback(.success, trigger: canStart) { old, new in haptics && !old && new }
    }
    .background(.black)
    .preferredColorScheme(.dark)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar { captureToolbar }
    .onChange(of: promptsVisible) { _, visible in pauseCapture(visible) }
    .sheet(isPresented: $showingHelp) { help }
    .task(id: readyObservation) {
      guard let observedAt = readyObservation else { return }
      let now = ProcessInfo.processInfo.systemUptime
      guard status.canStart(now: now) else {
        expiredObservation = observedAt
        return
      }
      // Leave the exact 0.6-second boundary valid, then disable without polling.
      let delay = (observedAt + 0.6).nextUp - now
      do { try await Task.sleep(for: .seconds(max(0, delay))) } catch { return }
      guard !Task.isCancelled else { return }
      expiredObservation = observedAt
    }
  }

  private func controls(_ guidance: String, isPortrait: Bool, canStart: Bool) -> some View {
    let start = BodyScanPrimaryButton(title: "Start scan", enabled: canStart, action: performAction)
      .accessibilityIdentifier("scan.camera.action")
    let showStart = status.mode == .framing
    return VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ZStack(alignment: .topLeading) {
            Text(guidance)
              .font(.headline)
              .fixedSize(horizontal: false, vertical: true)
              .id(guidance)
              .transition(.opacity)
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("scan.camera.guidance")
          }
          .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: guidance)
          if status.mode == .framing && isPortrait && !canStart && !status.pendingStart {
            ProgressView(value: status.calibrationProgress)
              .accessibilityLabel("Steady position calibration")
              .accessibilityIdentifier("scan.calibration")
          } else if status.mode == .initializing || status.mode == .finishing {
            ProgressView().accessibilityHidden(true)
          }
          if typeSize.isAccessibilitySize && (status.mode == .capturing || status.mode == .finishing || !status.completedViews.isEmpty || !status.missingAngles.isEmpty) {
            viewProgress
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
      .scrollBounceBehavior(.basedOnSize)

      if showStart {
        start
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
      } else if !typeSize.isAccessibilitySize && (status.mode == .capturing || status.mode == .finishing) {
        viewProgress
          .padding(.horizontal, 16)
          .padding(.bottom, 20)
      }
    }
  }

  @ToolbarContentBuilder private var captureToolbar: some ToolbarContent {
    ToolbarItem(placement: .cancellationAction) {
      Button("Close scan", systemImage: "xmark", action: close)
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("scan.close")
    }
    ToolbarItem(placement: .topBarTrailing) {
      Menu {
        Button("Scan help", systemImage: "info") { showingHelp = true }
        Toggle("Guidance haptics", isOn: $haptics)
      } label: {
        Label("Scan options", systemImage: "ellipsis").labelStyle(.iconOnly)
      }
      .accessibilityIdentifier("scan.options")
    }
  }

  private var viewProgress: some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
    let needed = status.neededView
    return layout {
      ForEach(BodyCaptureView.allCases, id: \.rawValue) { view in
        let targeted = view == needed
        let captured = status.completedViews.contains(view) && !targeted
        VStack(alignment: .leading, spacing: 4) {
          Capsule()
            .fill(targeted ? Color.clear : captured ? Color.accentColor : Color.secondary.opacity(0.18))
            .overlay { if targeted { Capsule().strokeBorder(Color.primary, lineWidth: 1.5) } }
            .frame(height: 4)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            if captured { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
            Text(view.title)
              .font(.caption.weight(captured || targeted ? .semibold : .regular))
              .fixedSize(horizontal: false, vertical: true)
          }
          .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Captured views")
    .accessibilityValue(status.viewsAccessibilityValue)
    .accessibilityIdentifier("scan.views")
    .animation(reduceMotion ? nil : .smooth, value: status.completedViews)
  }

  private var help: some View {
    NavigationStack {
      List {
        Section("Frame") {
          Text("Ask a helper to hold iPhone. Fit the whole person inside the camera view, from head to toe.")
          Text("Hold iPhone steady. When Start scan is enabled, tap it to lock this viewpoint.")
        }
        Section("Turn") {
          Text("Keep iPhone in the same spot. Ask the person to turn slowly with arms slightly away from the body.")
          Text("The ring fills as clear views are saved. The white marker points to a missing angle; follow the instruction to fill that gap.")
          Text("Relay the on-screen instruction. If a view is missing, follow the highlighted view. Other views are kept.")
        }
        Section("Review") {
          Text("Wait for the scan check to finish before handing the phone back. Review the scan before choosing whether to use it.")
        }
      }
      .navigationTitle("Scan help").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHelp = false } } }
    }
    .presentationDetents([.medium, .large])
  }
}
