import SwiftUI

@MainActor
struct ScanWarningOverlay: View {
  private struct RunState: Equatable {
    var position: ScanPositionFeedback
    var active: Bool
    var enabled: Bool
    var foreground: Bool
  }

  var position: ScanPositionFeedback
  var active = true
  @AppStorage("on-you.capture-haptics") private var hapticsEnabled = true
  @Environment(\.scenePhase) private var scenePhase
  @State private var feedback = ScanHapticFeedback()
  @State private var uptime = ProcessInfo.processInfo.systemUptime

  private var runState: RunState {
    RunState(position: position, active: active, enabled: hapticsEnabled, foreground: scenePhase == .active)
  }
  private var showsWarning: Bool {
    guard active, scenePhase == .active, position.direction != .hold, position.direction != .searching,
          position.intensity > 0, let observedAt = position.observedAt,
          observedAt.isFinite, uptime >= observedAt else { return false }
    return uptime - observedAt <= 0.6
  }

  var body: some View {
    Group {
      if showsWarning {
        Rectangle()
          .stroke(.red.opacity(0.18 + 0.5 * position.intensity), lineWidth: 48)
          .blur(radius: 20)
          .clipped()
      }
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
    .onAppear {
      uptime = ProcessInfo.processInfo.systemUptime
      synchronize(runState, now: uptime)
    }
    .onChange(of: runState) { _, state in
      uptime = ProcessInfo.processInfo.systemUptime
      synchronize(state, now: uptime)
    }
    .task(id: runState) {
      guard runState.active, runState.foreground, runState.position.intensity > 0,
            runState.position.observedAt != nil else {
        feedback.stop()
        return
      }
      while !Task.isCancelled {
        let now = ProcessInfo.processInfo.systemUptime
        uptime = now
        guard let observedAt = runState.position.observedAt,
              now >= observedAt, now - observedAt <= 0.6 else {
          feedback.stop()
          return
        }
        if runState.enabled { synchronize(runState, now: now) }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      }
    }
    .onDisappear { feedback.reset() }
  }

  private func synchronize(_ state: RunState, now: TimeInterval) {
    guard state.active, state.foreground else {
      feedback.reset()
      return
    }
    feedback.update(position: state.position, active: state.active, enabled: state.enabled,
                    foreground: state.foreground, now: now)
  }
}
