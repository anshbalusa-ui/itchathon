#if DEBUG
import XCTest
@testable import FitCheck

final class AvatarCaptureCoordinatorTests: XCTestCase {
    private let referenceAnchor = ScanStabilityAnchor(
        center: ScanPoint(x: 0.5, y: 0.5),
        height: 0.75,
        depth: 2,
        cameraPosition: ScanVector(x: 0, y: 0, z: 0),
        cameraForward: ScanVector(x: 0, y: 0, z: -1)
    )

    func testFrontThenSideRequiresCorrectViewsCountAndStableDuration() {
        var coordinator = startedCoordinator(requiredFrames: 3, requiredStableDuration: 0.8)
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(submit(&coordinator, at: 1.4, view: .front))
        XCTAssertEqual(submit(&coordinator, at: 1.9, view: .front), .front)
        XCTAssertEqual(coordinator.phase, .scanning(.side))
        XCTAssertEqual(coordinator.latestRejection, nil)

        XCTAssertNil(submit(&coordinator, at: 2.2, view: .side))
        XCTAssertNil(submit(&coordinator, at: 2.6, view: .side))
        XCTAssertEqual(submit(&coordinator, at: 3.1, view: .side), .side)
        XCTAssertEqual(coordinator.phase, .candidatePairReady)
        XCTAssertNil(coordinator.beginFrame(timestamp: 3.5, receivedAt: 3.5))
    }

    func testCumulativeMotionCannotMasqueradeAsStableFrames() {
        var coordinator = startedCoordinator()
        XCTAssertNil(submit(&coordinator, at: 1, view: .front, anchor: anchor(centerX: 0.5)))
        XCTAssertNil(submit(&coordinator, at: 1.4, view: .front, anchor: anchor(centerX: 0.515)))
        XCTAssertNil(submit(&coordinator, at: 1.9, view: .front, anchor: anchor(centerX: 0.53)))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(&coordinator, at: 2.2, view: .front, anchor: anchor(centerX: 0.53)))
        XCTAssertNil(submit(&coordinator, at: 2.6, view: .front, anchor: anchor(centerX: 0.53)))
        XCTAssertEqual(submit(&coordinator, at: 3.1, view: .front, anchor: anchor(centerX: 0.53)), .front)
    }

    func testFrameCountAloneCannotMeetStabilityDuration() {
        var coordinator = startedCoordinator(
            requiredFrames: 3,
            requiredStableDuration: 0.8,
            minimumFrameSpacing: 0.1
        )
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(submit(&coordinator, at: 1.2, view: .front))
        XCTAssertNil(submit(&coordinator, at: 1.4, view: .front))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertEqual(submit(&coordinator, at: 1.8, view: .front), .front)
    }

    func testWrongUnknownAndRepeatedFrontViewsNeverAdvanceSideCapture() {
        var coordinator = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        XCTAssertNil(submit(&coordinator, at: 1, view: .side))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
        XCTAssertEqual(coordinator.latestRejection, .wrongView)
        XCTAssertNil(submit(&coordinator, at: 1.3, view: .unverified))
        XCTAssertEqual(coordinator.latestRejection, .unverifiedView)
        XCTAssertEqual(submit(&coordinator, at: 1.6, view: .front), .front)

        XCTAssertNil(submit(&coordinator, at: 1.9, view: .front))
        XCTAssertEqual(coordinator.phase, .scanning(.side))
        XCTAssertEqual(coordinator.latestRejection, .wrongView)
        XCTAssertNil(submit(&coordinator, at: 2.2, view: .unverified))
        XCTAssertEqual(coordinator.latestRejection, .unverifiedView)
        XCTAssertEqual(coordinator.phase, .scanning(.side))
    }

    func testAssessmentRejectionsResetStabilityAndExposeReason() {
        let rejections: [ScanRejection] = [
            .missingPerson, .multiplePeople, .incompleteFraming, .unreliablePose,
            .invalidAlignment, .unavailableDepth, .insufficientPersonDepth,
            .trackingLimited, .unsupportedOrientation
        ]
        for rejection in rejections {
            var coordinator = startedCoordinator(requiredFrames: 3, requiredStableDuration: 0)
            XCTAssertNil(submit(&coordinator, at: 1, view: .front))
            XCTAssertNil(submit(&coordinator, at: 1.4, view: .front))
            XCTAssertNil(submit(&coordinator, at: 1.8, view: .front, rejection: rejection))
            XCTAssertEqual(coordinator.latestRejection, rejection)
            XCTAssertEqual(coordinator.phase, .scanning(.front))

            XCTAssertNil(submit(&coordinator, at: 2.2, view: .front))
            XCTAssertNil(submit(&coordinator, at: 2.6, view: .front))
            XCTAssertEqual(submit(&coordinator, at: 3, view: .front), .front)
        }
    }

    func testMissingAnchorAndNonfiniteAnchorAreRejected() {
        var coordinator = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        let missingAnchorTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 1, receivedAt: 1))
        XCTAssertNil(coordinator.accept(
            ticket: missingAnchorTicket,
            assessment: ScanFrameAssessment(
                timestamp: 1, rejection: nil, view: .front, anchor: nil
            ),
            now: 1.01
        ))
        XCTAssertEqual(coordinator.latestRejection, .unreliablePose)

        let invalidAnchorTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 1.3, receivedAt: 1.3))
        let invalidAnchor = ScanStabilityAnchor(
            center: ScanPoint(x: .nan, y: 0.5),
            height: 0.75,
            depth: 2,
            cameraPosition: ScanVector(x: 0, y: 0, z: 0),
            cameraForward: ScanVector(x: 0, y: 0, z: -1)
        )
        XCTAssertNil(coordinator.accept(
            ticket: invalidAnchorTicket,
            assessment: ScanFrameAssessment(
                timestamp: 1.3, rejection: nil, view: .front, anchor: invalidAnchor
            ),
            now: 1.31
        ))
        XCTAssertEqual(coordinator.latestRejection, .invalidAlignment)
        XCTAssertEqual(coordinator.phase, .scanning(.front))
    }

    func testMissingPersonAfterFrontInvalidatesPairAndRequiresRetry() {
        var coordinator = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        XCTAssertEqual(submit(&coordinator, at: 1, view: .front), .front)
        let sideTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 1.3, receivedAt: 1.3))
        let oldGeneration = coordinator.generation
        XCTAssertNil(coordinator.accept(
            ticket: sideTicket,
            assessment: assessment(1.3, view: .side, rejection: .missingPerson),
            now: 1.31
        ))
        XCTAssertEqual(coordinator.phase, .retryRequired(.personLost))
        XCTAssertGreaterThan(coordinator.generation, oldGeneration)
        XCTAssertEqual(coordinator.latestRejection, .missingPerson)
        XCTAssertNil(coordinator.accept(
            ticket: sideTicket,
            assessment: assessment(1.3, view: .side),
            now: 1.32
        ))
    }

    func testSubjectAndCameraMovementResetStability() {
        var coordinator = startedCoordinator(
            requiredFrames: 2,
            requiredStableDuration: 0.1,
            minimumFrameSpacing: 0.1
        )
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(submit(
            &coordinator, at: 1.2, view: .front,
            anchor: anchor(centerX: 0.56)
        ))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(
            &coordinator, at: 1.4, view: .front,
            anchor: anchor(cameraPosition: ScanVector(x: 0.2, y: 0, z: 0))
        ))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(&coordinator, at: 1.6, view: .front))
        XCTAssertNil(submit(&coordinator, at: 1.8, view: .front))
        XCTAssertEqual(submit(&coordinator, at: 2, view: .front), .front)
    }

    func testHeightDepthAndCameraDirectionMotionResetStability() {
        var coordinator = startedCoordinator(
            requiredFrames: 2,
            requiredStableDuration: 0,
            minimumFrameSpacing: 0.1
        )
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(submit(&coordinator, at: 1.2, view: .front, anchor: anchor(height: 0.6)))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(&coordinator, at: 1.4, view: .front, anchor: anchor(depth: 2.5)))
        XCTAssertNil(submit(&coordinator, at: 1.6, view: .front))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)

        let turnedCamera = ScanVector(x: 0.259, y: 0, z: -0.966)
        XCTAssertNil(submit(
            &coordinator, at: 1.8, view: .front,
            anchor: anchor(cameraForward: turnedCamera)
        ))
        XCTAssertNil(submit(&coordinator, at: 2, view: .front))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(&coordinator, at: 2.2, view: .front))
        XCTAssertEqual(submit(&coordinator, at: 2.4, view: .front), .front)
    }


    func testSideMustRemainInFrontFramingAndCameraContext() {
        let turnedCamera = ScanVector(x: 0.259, y: 0, z: -0.966)
        let mismatchedAnchors = [
            anchor(centerX: 0.7),
            anchor(height: 0.5),
            anchor(depth: 2.5),
            anchor(cameraPosition: ScanVector(x: 0.3, y: 0, z: 0)),
            anchor(cameraForward: turnedCamera)
        ]

        for sideAnchor in mismatchedAnchors {
            var coordinator = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
            XCTAssertEqual(submit(&coordinator, at: 1, view: .front), .front)
            XCTAssertNil(submit(&coordinator, at: 1.3, view: .side, anchor: sideAnchor))
            XCTAssertEqual(coordinator.phase, .scanning(.side))
            XCTAssertEqual(coordinator.latestRejection, .holdStill)
            XCTAssertEqual(submit(&coordinator, at: 1.6, view: .side), .side)
            XCTAssertEqual(coordinator.phase, .candidatePairReady)
        }
    }

    func testLongGapStaleFutureAndInconsistentResultsResetStability() {
        var coordinator = startedCoordinator(
            requiredFrames: 3,
            requiredStableDuration: 0,
            maximumFrameGap: 0.8
        )
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(submit(&coordinator, at: 2, view: .front))
        XCTAssertEqual(coordinator.latestRejection, .holdStill)
        XCTAssertNil(submit(&coordinator, at: 2.3, view: .front))

        let staleTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 2.6, receivedAt: 2.6))
        XCTAssertNil(coordinator.accept(
            ticket: staleTicket,
            assessment: assessment(2.6, view: .front),
            now: 3.36
        ))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        let futureTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 2.9, receivedAt: 2.9))
        XCTAssertNil(coordinator.accept(
            ticket: futureTicket,
            assessment: assessment(2.9, view: .front),
            now: 2.8
        ))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        let inconsistentTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 3.2, receivedAt: 3.2))
        XCTAssertNil(coordinator.accept(
            ticket: inconsistentTicket,
            assessment: assessment(3.200_001, view: .front),
            now: 3.21
        ))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        XCTAssertEqual(coordinator.phase, .scanning(.front))
    }

    func testPendingTicketSuppressesDuplicateWorkAndDuplicateResults() {
        var coordinator = startedCoordinator(requiredFrames: 2, requiredStableDuration: 0)
        let ticket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 1, receivedAt: 1))
        XCTAssertNil(coordinator.beginFrame(timestamp: 1.1, receivedAt: 1.1))
        XCTAssertNil(coordinator.beginFrame(timestamp: 1.2, receivedAt: 1.2))
        XCTAssertNil(coordinator.accept(
            ticket: ticket,
            assessment: assessment(1, view: .front),
            now: 1.01
        ))
        XCTAssertNil(coordinator.accept(
            ticket: ticket,
            assessment: assessment(1, view: .front),
            now: 1.02
        ))
        XCTAssertNil(coordinator.beginFrame(timestamp: 1.2, receivedAt: 1.2))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
        XCTAssertEqual(coordinator.beginFrame(timestamp: 1.4, receivedAt: 1.4)?.sequence, 2)
    }

    func testDuplicateOutOfOrderAndNonfiniteFrameTimesAreRejected() {
        var coordinator = startedCoordinator(requiredFrames: 2, requiredStableDuration: 0)
        XCTAssertNil(submit(&coordinator, at: 1, view: .front))
        XCTAssertNil(coordinator.beginFrame(timestamp: 1, receivedAt: 1))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        XCTAssertNil(coordinator.beginFrame(timestamp: 0.9, receivedAt: 0.9))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        XCTAssertNil(coordinator.beginFrame(timestamp: .infinity, receivedAt: 1))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
        XCTAssertNil(submit(&coordinator, at: 1.4, view: .front))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
    }

    func testCancelAndInterruptionInvalidateTicketsAndRetryFromFront() {
        var cancelled = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        let oldTicket = try! XCTUnwrap(cancelled.beginFrame(timestamp: 1, receivedAt: 1))
        let oldGeneration = cancelled.generation
        cancelled.cancel()
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertGreaterThan(cancelled.generation, oldGeneration)
        XCTAssertNil(cancelled.accept(
            ticket: oldTicket, assessment: assessment(1, view: .front), now: 1.01
        ))
        XCTAssertEqual(cancelled.start(supported: true, permission: .authorized), .runSession(cancelled.generation))
        XCTAssertEqual(cancelled.phase, .scanning(.front))
        XCTAssertNil(cancelled.latestRejection)

        let interruptedTicket = try! XCTUnwrap(cancelled.beginFrame(timestamp: 2, receivedAt: 2))
        cancelled.interrupt(.backgrounded)
        XCTAssertEqual(cancelled.phase, .retryRequired(.backgrounded))
        XCTAssertNil(cancelled.accept(
            ticket: interruptedTicket,
            assessment: assessment(2, view: .front),
            now: 2.01
        ))
        XCTAssertEqual(cancelled.start(supported: true, permission: .authorized), .runSession(cancelled.generation))
        XCTAssertEqual(cancelled.phase, .scanning(.front))
    }

    func testInterruptionReasonsRetryAndTerminalPhasesDoNotResurrect() {
        for reason: ScanInterruption in [
            .backgrounded, .sessionInterrupted, .trackingFailed,
            .orientationChanged, .timedOut
        ] {
            var coordinator = startedCoordinator()
            coordinator.interrupt(reason)
            XCTAssertEqual(coordinator.phase, .retryRequired(reason))
            coordinator.interrupt(.sessionInterrupted)
            XCTAssertEqual(coordinator.phase, .retryRequired(reason))
        }

        var permissionPending = AvatarCaptureCoordinator()
        _ = permissionPending.start(supported: true, permission: .authorized)
        permissionPending.cancel()
        permissionPending.interrupt(.backgrounded)
        XCTAssertEqual(permissionPending.phase, .cancelled)

        var candidate = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        XCTAssertEqual(submit(&candidate, at: 1, view: .front), .front)
        XCTAssertEqual(submit(&candidate, at: 1.3, view: .side), .side)
        let generation = candidate.generation
        candidate.interrupt(.backgrounded)
        XCTAssertEqual(candidate.phase, .candidatePairReady)
        XCTAssertEqual(candidate.generation, generation)
        candidate.cancel()
        XCTAssertEqual(candidate.phase, .cancelled, "Explicit discard must also clear a collected candidate")
        XCTAssertNil(candidate.beginFrame(timestamp: 2, receivedAt: 2))
    }

    func testStalePermissionAndFrameFromPreviousGenerationCannotAffectRetry() {
        var coordinator = AvatarCaptureCoordinator()
        let oldAction = coordinator.start(supported: true, permission: .notDetermined)
        guard case .requestPermission(let oldGeneration) = oldAction else {
            return XCTFail("Expected a permission request")
        }
        coordinator.interrupt(.backgrounded)
        let newAction = coordinator.start(supported: true, permission: .authorized)
        guard case .runSession(let newGeneration) = newAction else {
            return XCTFail("Expected a fresh session")
        }
        XCTAssertNotEqual(oldGeneration, newGeneration)
        XCTAssertFalse(coordinator.resolvePermission(granted: true, generation: oldGeneration))
        XCTAssertEqual(coordinator.phase, .scanning(.front))

        let oldTicket = try! XCTUnwrap(coordinator.beginFrame(timestamp: 1, receivedAt: 1))
        coordinator.interrupt(.trackingFailed)
        _ = coordinator.start(supported: true, permission: .authorized)
        XCTAssertNil(coordinator.accept(
            ticket: oldTicket,
            assessment: assessment(1, view: .front),
            now: 1.01
        ))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
        XCTAssertEqual(coordinator.generation, newGeneration + 2)
    }

    func testUnsupportedDeniedRestrictedAndDuplicateStartPolicies() {
        var unsupported = AvatarCaptureCoordinator()
        XCTAssertEqual(
            unsupported.start(supported: false, permission: .notDetermined),
            .none
        )
        XCTAssertEqual(unsupported.phase, .unavailable(.unsupportedDevice))
        XCTAssertNil(unsupported.beginFrame(timestamp: 1, receivedAt: 1))

        var denied = AvatarCaptureCoordinator()
        XCTAssertEqual(denied.start(supported: true, permission: .denied), .none)
        XCTAssertEqual(denied.phase, .unavailable(.cameraDenied))
        var restricted = AvatarCaptureCoordinator()
        XCTAssertEqual(restricted.start(supported: true, permission: .restricted), .none)
        XCTAssertEqual(restricted.phase, .unavailable(.cameraRestricted))

        var permission = AvatarCaptureCoordinator()
        let request = permission.start(supported: true, permission: .notDetermined)
        XCTAssertEqual(request, .requestPermission(permission.generation))
        XCTAssertEqual(
            permission.start(supported: true, permission: .authorized),
            .none
        )
        XCTAssertEqual(permission.phase, .requestingPermission)
        XCTAssertFalse(permission.resolvePermission(granted: true, generation: permission.generation + 1))
        XCTAssertTrue(permission.resolvePermission(granted: true, generation: permission.generation))
        XCTAssertEqual(
            permission.start(supported: true, permission: .authorized),
            .none
        )
        XCTAssertFalse(permission.resolvePermission(granted: true, generation: permission.generation))
        XCTAssertEqual(permission.phase, .scanning(.front))
    }

    func testPermissionDenialResolutionIsRetryable() {
        var coordinator = AvatarCaptureCoordinator()
        let request = coordinator.start(supported: true, permission: .notDetermined)
        guard case .requestPermission(let generation) = request else {
            return XCTFail("Expected a permission request")
        }
        XCTAssertFalse(coordinator.resolvePermission(granted: false, generation: generation))
        XCTAssertEqual(coordinator.phase, .unavailable(.cameraDenied))
        XCTAssertEqual(coordinator.start(supported: true, permission: .authorized), .runSession(coordinator.generation))
        XCTAssertEqual(coordinator.phase, .scanning(.front))
    }

    func testFreshnessDoesNotAssumeMatchingCameraAndAdmissionClockEpochs() throws {
        var coordinator = startedCoordinator(requiredFrames: 1, requiredStableDuration: 0)
        let front = try XCTUnwrap(coordinator.beginFrame(timestamp: 1, receivedAt: 5_000))
        XCTAssertEqual(coordinator.accept(
            ticket: front, assessment: assessment(1, view: .front), now: 5_000.01
        ), .front)
        let side = try XCTUnwrap(coordinator.beginFrame(timestamp: 1.3, receivedAt: 5_000.3))
        XCTAssertNil(coordinator.accept(
            ticket: side, assessment: assessment(1.3, view: .side), now: 5_002
        ))
        XCTAssertEqual(coordinator.phase, .scanning(.side))
        XCTAssertEqual(coordinator.latestRejection, .staleFrame)
    }

    private func startedCoordinator(
        requiredFrames: Int = 3,
        requiredStableDuration: Double = 0.8,
        minimumFrameSpacing: Double = 0.25,
        maximumFrameGap: Double = 0.8,
        maximumResultAge: Double = 0.75
    ) -> AvatarCaptureCoordinator {
        var coordinator = AvatarCaptureCoordinator(
            requiredFrames: requiredFrames,
            requiredStableDuration: requiredStableDuration,
            minimumFrameSpacing: minimumFrameSpacing,
            maximumFrameGap: maximumFrameGap,
            maximumResultAge: maximumResultAge
        )
        _ = coordinator.start(supported: true, permission: .authorized)
        return coordinator
    }

    private func submit(
        _ coordinator: inout AvatarCaptureCoordinator,
        at timestamp: Double,
        view: ScanViewEstimate,
        rejection: ScanRejection? = nil,
        anchor: ScanStabilityAnchor? = nil
    ) -> ScanCaptureView? {
        guard let ticket = coordinator.beginFrame(timestamp: timestamp, receivedAt: timestamp) else { return nil }
        return coordinator.accept(
            ticket: ticket,
            assessment: assessment(
                timestamp,
                view: view,
                rejection: rejection,
                anchor: anchor ?? referenceAnchor
            ),
            now: timestamp + 0.01
        )
    }

    private func assessment(
        _ timestamp: Double,
        view: ScanViewEstimate,
        rejection: ScanRejection? = nil,
        anchor: ScanStabilityAnchor? = nil
    ) -> ScanFrameAssessment {
        ScanFrameAssessment(
            timestamp: timestamp,
            rejection: rejection,
            view: view,
            anchor: anchor ?? referenceAnchor
        )
    }

    private func anchor(
        centerX: Double = 0.5,
        height: Double = 0.75,
        depth: Double = 2,
        cameraPosition: ScanVector = ScanVector(x: 0, y: 0, z: 0),
        cameraForward: ScanVector = ScanVector(x: 0, y: 0, z: -1)
    ) -> ScanStabilityAnchor {
        ScanStabilityAnchor(
            center: ScanPoint(x: centerX, y: 0.5),
            height: height,
            depth: depth,
            cameraPosition: cameraPosition,
            cameraForward: cameraForward
        )
    }
}
#endif
