import CoreHaptics
import Foundation
import OSLog

@MainActor
final class ScanHapticFeedback {
  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "OnYou", category: "ScanGuidance")
  private var engine: CHHapticEngine?
  private var player: CHHapticAdvancedPatternPlayer?
  private var engineGeneration = 0
  private(set) var playing = false
  private var failed = false
  private var unsupported = false
  private var lastIntensity: Float?

  func update(position: ScanPositionFeedback, active: Bool, enabled: Bool, foreground: Bool, now: TimeInterval) {
    guard active, enabled, foreground, now.isFinite,
          let observedAt = position.observedAt, observedAt.isFinite,
          now >= observedAt, now - observedAt <= 0.6,
          position.intensity > 0, !failed, !unsupported else {
      stop()
      return
    }
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
      unsupported = true
      logger.warning("Core Haptics unavailable on this device")
      stop()
      return
    }
    guard startPlayer() else { return }

    let intensity = Float(0.24 + 0.76 * position.intensity)
    guard lastIntensity.map({ abs($0 - intensity) >= 0.015 }) ?? true else { return }
    do {
      try player?.sendParameters([
        CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
        CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(0.28 + 0.32 * position.intensity), relativeTime: 0)
      ], atTime: CHHapticTimeImmediate)
      lastIntensity = intensity
    } catch {
      logger.error("Core Haptics intensity update failed: \(error.localizedDescription, privacy: .public)")
      fail()
    }
  }

  func stop() {
    guard playing else { return }
    do {
      try player?.stop(atTime: CHHapticTimeImmediate)
    } catch {
      logger.error("Core Haptics stop failed: \(error.localizedDescription, privacy: .public)")
    }
    playing = false
    lastIntensity = nil
  }

  func reset() {
    stop()
    engineGeneration += 1
    let engine = self.engine
    engine?.resetHandler = {}
    engine?.stoppedHandler = { _ in }
    do {
      try engine?.stop()
    } catch {
      logger.error("Core Haptics engine shutdown failed: \(error.localizedDescription, privacy: .public)")
    }
    self.engine = nil
    player = nil
    failed = false
    unsupported = false
    lastIntensity = nil
  }

  private func startPlayer() -> Bool {
    if let engine, let player {
      guard !playing else { return true }
      do {
        try engine.start()
        try player.start(atTime: CHHapticTimeImmediate)
        playing = true
        return true
      } catch {
        logger.error("Core Haptics restart failed: \(error.localizedDescription, privacy: .public)")
        fail()
        return false
      }
    }

    do {
      let engine = try CHHapticEngine()
      engine.playsHapticsOnly = true
      engineGeneration += 1
      let generation = engineGeneration
      engine.resetHandler = { [weak self] in
        Task { @MainActor [weak self] in self?.engineDidReset(generation: generation) }
      }
      engine.stoppedHandler = { [weak self] reason in
        Task { @MainActor [weak self] in self?.engineDidStop(reason, generation: generation) }
      }
      let event = CHHapticEvent(eventType: .hapticContinuous,
                                parameters: [
                                  CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                                  CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                                ], relativeTime: 0, duration: 1)
      let pattern = try CHHapticPattern(events: [event], parameters: [])
      let player = try engine.makeAdvancedPlayer(with: pattern)
      player.loopEnabled = true
      player.loopEnd = 1
      self.engine = engine
      self.player = player
      try engine.start()
      try player.start(atTime: CHHapticTimeImmediate)
      playing = true
      return true
    } catch {
      logger.error("Core Haptics startup failed: \(error.localizedDescription, privacy: .public)")
      fail()
      return false
    }
  }

  private func engineDidReset(generation: Int) {
    guard generation == engineGeneration else { return }
    logger.error("Core Haptics engine reset")
    engineGeneration += 1
    engine = nil
    player = nil
    playing = false
    failed = false
    lastIntensity = nil
  }

  private func engineDidStop(_ reason: CHHapticEngine.StoppedReason, generation: Int) {
    guard generation == engineGeneration else { return }
    logger.error("Core Haptics engine stopped: \(String(describing: reason), privacy: .public)")
    engineGeneration += 1
    engine = nil
    player = nil
    playing = false
    failed = false
    lastIntensity = nil
  }

  private func fail() {
    stop()
    engineGeneration += 1
    let engine = self.engine
    engine?.resetHandler = {}
    engine?.stoppedHandler = { _ in }
    do {
      try engine?.stop()
    } catch {
      logger.error("Core Haptics engine stop after failure failed: \(error.localizedDescription, privacy: .public)")
    }
    self.engine = nil
    player = nil
    failed = true
    lastIntensity = nil
  }
}
