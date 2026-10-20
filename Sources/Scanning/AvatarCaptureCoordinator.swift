import Foundation

/// A two-view capture sequence. A completed sequence is evidence for later
/// avatar estimation, not an accurate body mesh or fit prediction.
enum AvatarCapturePhase: Equatable {
    case front
    case side
    case complete
}

struct AvatarFrameReadiness: Equatable {
    var fullPersonVisible: Bool
    var poseReliable: Bool
    var depthUsable: Bool
    var stable: Bool

    var canCapture: Bool {
        fullPersonVisible && poseReliable && depthUsable && stable
    }
}

/// Pure state machine, independent of ARKit, for deterministic unit tests.
struct AvatarCaptureCoordinator {
    private(set) var phase: AvatarCapturePhase = .front
    private(set) var consecutiveReadyFrames = 0
    let requiredFrames: Int

    init(requiredFrames: Int = 5) {
        self.requiredFrames = max(2, requiredFrames)
    }

    /// Returns the phase just captured, if one view became ready.
    mutating func accept(_ readiness: AvatarFrameReadiness) -> AvatarCapturePhase? {
        guard phase != .complete else { return nil }
        guard readiness.canCapture else {
            consecutiveReadyFrames = 0
            return nil
        }
        consecutiveReadyFrames += 1
        guard consecutiveReadyFrames >= requiredFrames else { return nil }

        consecutiveReadyFrames = 0
        let captured = phase
        phase = captured == .front ? .side : .complete
        return captured
    }

    mutating func reset() {
        phase = .front
        consecutiveReadyFrames = 0
    }
}
