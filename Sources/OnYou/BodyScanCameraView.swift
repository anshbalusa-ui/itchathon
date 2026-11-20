import SwiftUI

struct BodyScanCameraView<Camera: View>: View {
  var status: BodyScanCameraStatus
  var position = ScanPositionFeedback()
  var close: () -> Void
  var performAction: () -> Void
  var paused = false
  var pauseCapture: (Bool) -> Void = { _ in }
  var announceInstruction: (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
  @ViewBuilder var camera: () -> Camera
  @AppStorage("on-you.capture-haptics") private var haptics = true
  @AppStorage("on-you.capture-speech") private var spokenGuidance = true
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
    status.mode == .framing && status.calibrated ? status.observedAt : nil
  }

  private func instruction(isPortrait: Bool) -> String {
    switch status.mode {
    case .initializing: "Getting the camera ready…"
    case .finishing: "Checking your scan…"
    case .framing, .capturing:
      if !isPortrait { "Keep iPhone upright on its support." }
      else if let seconds = status.countdown { "Starting in \(seconds)… Step into view." }
      else if status.start == .starting { "Starting scan…" }
      else if status.calibrated && status.observedAt == expiredObservation {
        "Waiting for a fresh camera view. Keep your head and feet visible."
      }
      else if status.start == .waitingForFraming { "Scan armed. \(status.instruction)" }
      else { status.instruction }
    }
  }

  var body: some View {
    GeometryReader { geometry in
      let isPortrait = geometry.size.height > geometry.size.width
      let guidance = instruction(isPortrait: isPortrait)
      let canAct = isPortrait && guidanceActive && (status.canArmStart || status.canCancelStart)
      let ready = isPortrait && guidanceActive && !status.pendingStart
        && status.observedAt != expiredObservation
        && status.hasFreshCalibration(now: ProcessInfo.processInfo.systemUptime)
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
        controls(guidance, isPortrait: isPortrait, canAct: canAct, ready: ready)
          .frame(width: isPortrait ? nil : geometry.size.width * 0.44,
                 height: isPortrait ? min(controlsHeight, geometry.size.height / 2) : nil)
          .background(.black)
      }
      .onChange(of: guidance) { _, instruction in
        if !promptsVisible && scenePhase == .active && status.mode != .finishing {
          announceInstruction(instruction)
        }
      }
      .sensoryFeedback(.success, trigger: ready) { old, new in haptics && !old && new }
    }
    .background(.black)
    .preferredColorScheme(.dark)
    .toolbarColorScheme(.dark, for: .navigationBar)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar { captureToolbar }
    .onChange(of: promptsVisible) { _, visible in pauseCapture(visible || scenePhase != .active) }
    .onChange(of: scenePhase) { _, phase in pauseCapture(promptsVisible || phase != .active) }
    .sheet(isPresented: $showingHelp) { help }
    .task(id: readyObservation) {
      guard let observedAt = readyObservation else { return }
      let now = ProcessInfo.processInfo.systemUptime
      guard status.hasFreshCalibration(now: now) else {
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

  private func controls(_ guidance: String, isPortrait: Bool, canAct: Bool, ready: Bool) -> some View {
    let title = status.canCancelStart ? "Cancel start" : status.start == .starting ? "Starting scan…" : "Start scan"
    let start = BodyScanPrimaryButton(title: title, enabled: canAct, action: performAction)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityIdentifier("scan.camera.action")
    let showStart = status.mode == .framing
    return VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if showStart && typeSize.isAccessibilitySize {
            // Keep the action reachable first; scroll guidance and wrapped labels together.
            start.padding(.bottom, 6)
          }
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
          if status.mode == .framing && !status.pendingStart {
            Text("Set iPhone upright on a stable surface, with the rear camera facing you. Tap Start scan, then step into view.")
              .font(.callout).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          if status.mode == .framing && isPortrait && !ready && status.countdown == nil && status.start != .starting {
            ProgressView(value: status.calibrationProgress)
              .accessibilityLabel("Steady position calibration")
              .accessibilityIdentifier("scan.calibration")
          } else if status.mode == .initializing || status.mode == .finishing || status.start == .starting {
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

      if showStart && !typeSize.isAccessibilitySize {
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
        Toggle("Spoken guidance", isOn: $spokenGuidance)
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
        Section("Place iPhone") {
          Text("Prop iPhone upright on a secure, stable surface with the rear camera facing you. Keep the phone fixed while you turn.")
          Text("Leave room above your head, below your feet and beside your arms. Use even light and a clear background.")
          Text("Tap Start scan, then step into view during the five-second countdown. Capture waits until you are facing the camera with your whole body framed and arms slightly away.")
          Text("Turn up the volume for spoken guidance, or use VoiceOver. Spoken guidance and haptics can be changed in Scan options.")
        }
        Section("Turn") {
          Text("Turn slowly in place with arms slightly away from your body. Turn your shoulders, arms and torso together without changing your pose.")
          Text("The ring fills only as clear views are saved. Follow the highlighted missing view; other accepted views are kept.")
          Text("Capture moves to processing automatically when enough usable views are collected.")
        }
        Section("If space is limited") {
          Text("Before starting, reposition iPhone or choose a clearer area so your head and feet fit with usable depth. A full-body view is required; reposition or retry rather than continuing with a partial view.")
        }
        Section("Review") {
          Text("Keep On You open while it builds your avatar. Return to iPhone when it is ready, inspect the result, then choose whether to use it.")
        }
      }
      .navigationTitle("Scan help").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHelp = false } } }
    }
    .presentationDetents([.medium, .large])
  }
}
