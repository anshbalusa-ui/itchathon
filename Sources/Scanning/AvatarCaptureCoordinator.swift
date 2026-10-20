#if DEBUG
import Foundation

/// Deterministic policy for collecting two observational views. A candidate
/// pair is not a verified body model or an approved avatar.
struct AvatarCaptureCoordinator {
    private(set) var phase: ScanCapturePhase = .idle
    private(set) var generation: UInt64 = 0
    private(set) var latestRejection: ScanRejection?

    let requiredFrames: Int
    let requiredStableDuration: Double
    let minimumFrameSpacing: Double
    let maximumFrameGap: Double
    let maximumResultAge: Double

    private var nextSequence: UInt64 = 0
    private var pendingTicket: ScanFrameTicket?
    private var lastInputTimestamp: Double?
    private var lastStartedTimestamp: Double?
    private var stableStartTimestamp: Double?
    private var stableFrames = 0
    private var previousStableAnchor: ScanStabilityAnchor?
    private var stableReferenceAnchor: ScanStabilityAnchor?
    private var frontAnchor: ScanStabilityAnchor?

    init(
        requiredFrames: Int = 3,
        requiredStableDuration: Double = 0.8,
        minimumFrameSpacing: Double = 0.25,
        maximumFrameGap: Double = 0.8,
        maximumResultAge: Double = 0.75
    ) {
        self.requiredFrames = max(1, requiredFrames)
        self.requiredStableDuration = Self.validThreshold(requiredStableDuration, fallback: 0.8)
        self.minimumFrameSpacing = Self.validThreshold(minimumFrameSpacing, fallback: 0.25)
        self.maximumFrameGap = max(
            self.minimumFrameSpacing,
            Self.validThreshold(maximumFrameGap, fallback: 0.8)
        )
        self.maximumResultAge = Self.validThreshold(maximumResultAge, fallback: 0.75)
    }

    /// Starts a fresh attempt, or does nothing while permission/session startup
    /// is already in progress.
    mutating func start(supported: Bool, permission: ScanCameraPermission) -> ScanStartAction {
        guard phase != .requestingPermission, !Self.isScanning(phase) else { return .none }

        generation &+= 1
        resetAttemptState()
        latestRejection = nil

        guard supported else {
            phase = .unavailable(.unsupportedDevice)
            return .none
        }

        switch permission {
        case .notDetermined:
            phase = .requestingPermission
            return .requestPermission(generation)
        case .authorized:
            phase = .scanning(.front)
            return .runSession(generation)
        case .denied:
            phase = .unavailable(.cameraDenied)
            return .none
        case .restricted:
            phase = .unavailable(.cameraRestricted)
            return .none
        }
    }

    /// Resolves only the current permission request. A denial is distinct from
    /// a restricted device; the permission adapter supplies that initial state.
    @discardableResult
    mutating func resolvePermission(granted: Bool, generation replyGeneration: UInt64) -> Bool {
        guard case .requestingPermission = phase, replyGeneration == generation else { return false }
        guard granted else {
            phase = .unavailable(.cameraDenied)
            return false
        }
        phase = .scanning(.front)
        latestRejection = nil
        return true
    }

    /// Grants at most one analysis ticket at a time. Timestamps must be finite
    /// and strictly increasing; freshness uses a separate local admission clock.
    mutating func beginFrame(timestamp: Double, receivedAt: Double) -> ScanFrameTicket? {
        guard case .scanning(let view) = phase, pendingTicket == nil else { return nil }

        guard timestamp.isFinite, timestamp >= 0, receivedAt.isFinite, receivedAt >= 0 else {
            resetStability(rejection: .staleFrame)
            return nil
        }
        if let lastInputTimestamp, timestamp <= lastInputTimestamp {
            resetStability(rejection: .staleFrame)
            return nil
        }
        lastInputTimestamp = timestamp

        if let lastStartedTimestamp {
            let gap = timestamp - lastStartedTimestamp
            if gap > maximumFrameGap {
                resetStability(rejection: .holdStill)
            } else if gap < minimumFrameSpacing {
                return nil
            }
        }

        lastStartedTimestamp = timestamp
        nextSequence &+= 1
        let ticket = ScanFrameTicket(
            generation: generation,
            sequence: nextSequence,
            view: view,
            timestamp: timestamp,
            receivedAt: receivedAt
        )
        pendingTicket = ticket
        return ticket
    }

    /// Consumes only the currently outstanding result. Rejected, stale, or
    /// mismatched observations never contribute to stability.
    @discardableResult
    mutating func accept(
        ticket: ScanFrameTicket,
        assessment: ScanFrameAssessment,
        now: Double
    ) -> ScanCaptureView? {
        guard pendingTicket == ticket,
              ticket.generation == generation,
              case .scanning(let expectedView) = phase,
              ticket.view == expectedView
        else { return nil }
        pendingTicket = nil

        guard assessment.timestamp.isFinite,
              assessment.timestamp == ticket.timestamp,
              now.isFinite,
              now >= ticket.receivedAt,
              now - ticket.receivedAt <= maximumResultAge
        else {
            resetStability(rejection: .staleFrame)
            return nil
        }

        if let rejection = assessment.rejection {
            if rejection == .missingPerson, expectedView == .side {
                interrupt(.personLost)
                latestRejection = .missingPerson
            } else {
                resetStability(rejection: rejection)
            }
            return nil
        }

        guard assessment.view != .unverified else {
            resetStability(rejection: .unverifiedView)
            return nil
        }
        guard assessment.view == (expectedView == .front ? .front : .side) else {
            resetStability(rejection: .wrongView)
            return nil
        }
        guard let anchor = assessment.anchor else {
            resetStability(rejection: .unreliablePose)
            return nil
        }
        guard Self.isValid(anchor) else {
            resetStability(rejection: .invalidAlignment)
            return nil
        }
        if expectedView == .side,
           let frontAnchor,
           !Self.isSameFramingContext(frontAnchor, anchor) {
            resetStability(rejection: .holdStill)
            return nil
        }
        if let previousStableAnchor,
           !Self.isStable(previousStableAnchor, anchor) {
            resetStability(rejection: .holdStill)
            return nil
        }
        if let stableReferenceAnchor,
           !Self.isStable(stableReferenceAnchor, anchor) {
            resetStability(rejection: .holdStill)
            return nil
        }

        if stableFrames == 0 {
            stableStartTimestamp = ticket.timestamp
            stableReferenceAnchor = anchor
        }
        stableFrames += 1
        previousStableAnchor = anchor

        let duration = ticket.timestamp - (stableStartTimestamp ?? ticket.timestamp)
        guard stableFrames >= requiredFrames, duration >= requiredStableDuration else {
            latestRejection = .holdStill
            return nil
        }

        latestRejection = nil
        resetStability(rejection: nil)
        switch expectedView {
        case .front:
            frontAnchor = anchor
            phase = .scanning(.side)
            return .front
        case .side:
            phase = .candidatePairReady
            return .side
        }
    }

    /// Invalidates outstanding work and returns active captures to a retryable
    /// front-view attempt. Terminal states cannot be resurrected by callbacks.
    mutating func interrupt(_ reason: ScanInterruption) {
        guard Self.isScanning(phase) || phase == .requestingPermission else { return }
        generation &+= 1
        phase = .retryRequired(reason)
        resetAttemptState()
        latestRejection = nil
    }

    mutating func cancel() {
        guard phase != .cancelled else { return }
        generation &+= 1
        phase = .cancelled
        resetAttemptState()
        latestRejection = nil
    }

    private mutating func resetAttemptState() {
        nextSequence = 0
        pendingTicket = nil
        lastInputTimestamp = nil
        lastStartedTimestamp = nil
        frontAnchor = nil
        resetStability(rejection: nil)
    }

    private mutating func resetStability(rejection: ScanRejection?) {
        stableStartTimestamp = nil
        stableFrames = 0
        previousStableAnchor = nil
        stableReferenceAnchor = nil
        latestRejection = rejection
    }

    private static func isScanning(_ phase: ScanCapturePhase) -> Bool {
        if case .scanning = phase { return true }
        return false
    }

    private static func validThreshold(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value >= 0 ? value : fallback
    }

    private static func isValid(_ anchor: ScanStabilityAnchor) -> Bool {
        guard anchor.center.x.isFinite, anchor.center.y.isFinite,
              anchor.height.isFinite, anchor.depth.isFinite,
              anchor.cameraPosition.x.isFinite, anchor.cameraPosition.y.isFinite, anchor.cameraPosition.z.isFinite,
              anchor.cameraForward.x.isFinite, anchor.cameraForward.y.isFinite, anchor.cameraForward.z.isFinite,
              (0...1).contains(anchor.center.x),
              (0...1).contains(anchor.center.y),
              anchor.height > 0,
              anchor.height <= 1,
              anchor.depth > 0
        else { return false }
        let positionLength = vectorLength(anchor.cameraPosition)
        let forwardLength = vectorLength(anchor.cameraForward)
        return positionLength.isFinite && forwardLength.isFinite && forwardLength > 0
    }

    /// Tight frame-to-frame bounds reject camera motion and noticeable subject
    /// movement while allowing small sensor jitter.
    private static func isStable(
        _ lhs: ScanStabilityAnchor,
        _ rhs: ScanStabilityAnchor
    ) -> Bool {
        pointDistance(lhs.center, rhs.center) <= 0.025
            && relativeDifference(lhs.height, rhs.height) <= 0.06
            && abs(lhs.depth - rhs.depth) <= 0.12
            && vectorDistance(lhs.cameraPosition, rhs.cameraPosition) <= 0.06
            && directionAngle(lhs.cameraForward, rhs.cameraForward) <= 4 * .pi / 180
    }

    /// Side evidence must still be from the front capture's broad framing,
    /// range, and camera context; bounds are intentionally looser for a turn.
    private static func isSameFramingContext(
        _ front: ScanStabilityAnchor,
        _ side: ScanStabilityAnchor
    ) -> Bool {
        pointDistance(front.center, side.center) <= 0.10
            && relativeDifference(front.height, side.height) <= 0.20
            && abs(front.depth - side.depth) <= 0.25
            && vectorDistance(front.cameraPosition, side.cameraPosition) <= 0.20
            && directionAngle(front.cameraForward, side.cameraForward) <= 10 * .pi / 180
    }

    private static func pointDistance(_ lhs: ScanPoint, _ rhs: ScanPoint) -> Double {
        let x = lhs.x - rhs.x
        let y = lhs.y - rhs.y
        return (x * x + y * y).squareRoot()
    }

    private static func vectorDistance(_ lhs: ScanVector, _ rhs: ScanVector) -> Double {
        let x = lhs.x - rhs.x
        let y = lhs.y - rhs.y
        let z = lhs.z - rhs.z
        return (x * x + y * y + z * z).squareRoot()
    }

    private static func vectorLength(_ vector: ScanVector) -> Double {
        let scale = max(abs(vector.x), max(abs(vector.y), abs(vector.z)))
        guard scale > 0 else { return 0 }
        let x = vector.x / scale
        let y = vector.y / scale
        let z = vector.z / scale
        return scale * (x * x + y * y + z * z).squareRoot()
    }

    private static func relativeDifference(_ lhs: Double, _ rhs: Double) -> Double {
        abs(lhs - rhs) / max(lhs, rhs)
    }

    private static func directionAngle(_ lhs: ScanVector, _ rhs: ScanVector) -> Double {
        let lhsLength = vectorLength(lhs)
        let rhsLength = vectorLength(rhs)
        let dot = (lhs.x / lhsLength) * (rhs.x / rhsLength)
            + (lhs.y / lhsLength) * (rhs.y / rhsLength)
            + (lhs.z / lhsLength) * (rhs.z / rhsLength)
        let cosine = min(1, max(-1, dot))
        return acos(cosine)
    }
}
#endif
