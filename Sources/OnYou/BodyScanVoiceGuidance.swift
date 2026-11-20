import AVFoundation
import SwiftUI
import UIKit

/// One speaker for the scan presentation, with at most one pending instruction.
/// VoiceOver owns announcements when running; no microphone or recorded audio.
@MainActor
final class BodyScanVoiceGuidance: NSObject, AVSpeechSynthesizerDelegate {
  private var synthesizer: AVSpeechSynthesizer?
  private var enabled = false
  private var active = false
  private var lastMessage: String?
  private var pendingMessage: String?

  func configure(enabled: Bool, active: Bool) {
    self.enabled = enabled
    self.active = active
    if !active || !enabled || UIAccessibility.isVoiceOverRunning {
      pendingMessage = nil
      synthesizer?.stopSpeaking(at: .immediate)
      lastMessage = nil
    }
  }

  func countdown(_ seconds: Int) {
    switch seconds {
    case 5: announce("Step into view and face the camera.", interrupt: true)
    case 1...3: announce(String(seconds), interrupt: true)
    default: break
    }
  }

  func announce(_ message: String, interrupt: Bool = false) {
    guard active, !message.isEmpty else { return }
    if UIAccessibility.isVoiceOverRunning {
      guard message != lastMessage else { return }
      lastMessage = message
      AccessibilityNotification.Announcement(message).post()
      return
    }
    guard enabled else { return }
    if interrupt {
      pendingMessage = nil
      guard message != lastMessage else { return }
      synthesizer?.stopSpeaking(at: .immediate)
    } else if synthesizer?.isSpeaking == true {
      // Replace stale instructions rather than accumulating a speech backlog.
      pendingMessage = message == lastMessage ? nil : message
      return
    }
    guard message != lastMessage else { return }
    if synthesizer == nil {
      let speaker = AVSpeechSynthesizer()
      speaker.usesApplicationAudioSession = false
      speaker.delegate = self
      synthesizer = speaker
    }
    let utterance = AVSpeechUtterance(string: message)
    utterance.prefersAssistiveTechnologySettings = true
    lastMessage = message
    synthesizer?.speak(utterance)
  }

  private func finishInstruction() {
    guard active, enabled, !UIAccessibility.isVoiceOverRunning,
          synthesizer?.isSpeaking == false, let message = pendingMessage else { return }
    pendingMessage = nil
    announce(message)
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor [weak self] in self?.finishInstruction() }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor [weak self] in self?.finishInstruction() }
  }
}
