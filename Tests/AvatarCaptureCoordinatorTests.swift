import XCTest
@testable import FitCheck

final class AvatarCaptureCoordinatorTests: XCTestCase {
    private let ready = AvatarFrameReadiness(
        fullPersonVisible: true, poseReliable: true,
        depthUsable: true, stable: true
    )

    func testFrontThenSideCaptureNeedsConsecutiveGoodFrames() {
        var coordinator = AvatarCaptureCoordinator(requiredFrames: 3)
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertEqual(coordinator.phase, .front)
        XCTAssertEqual(coordinator.accept(ready), .front)
        XCTAssertEqual(coordinator.phase, .side)

        XCTAssertNil(coordinator.accept(ready))
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertEqual(coordinator.accept(ready), .side)
        XCTAssertEqual(coordinator.phase, .complete)
        XCTAssertNil(coordinator.accept(ready))
    }

    func testMissingDepthPreventsCaptureAndResetsStability() {
        var coordinator = AvatarCaptureCoordinator(requiredFrames: 3)
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertNil(coordinator.accept(ready))

        var withoutDepth = ready
        withoutDepth.depthUsable = false
        XCTAssertNil(coordinator.accept(withoutDepth))
        XCTAssertEqual(coordinator.consecutiveReadyFrames, 0)

        XCTAssertNil(coordinator.accept(ready))
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertEqual(coordinator.accept(ready), .front)
    }

    func testPersonPoseAndStillnessAreAllRequired() {
        for field in 0..<3 {
            var coordinator = AvatarCaptureCoordinator(requiredFrames: 2)
            var incomplete = ready
            switch field {
            case 0: incomplete.fullPersonVisible = false
            case 1: incomplete.poseReliable = false
            default: incomplete.stable = false
            }
            XCTAssertNil(coordinator.accept(incomplete))
            XCTAssertEqual(coordinator.phase, .front)
            XCTAssertEqual(coordinator.consecutiveReadyFrames, 0)
        }
    }

    func testResetRestartsAtFrontAndClearsEvidence() {
        var coordinator = AvatarCaptureCoordinator(requiredFrames: 2)
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertEqual(coordinator.accept(ready), .front)
        XCTAssertEqual(coordinator.phase, .side)
        XCTAssertNil(coordinator.accept(ready))
        coordinator.reset()
        XCTAssertEqual(coordinator.phase, .front)
        XCTAssertEqual(coordinator.consecutiveReadyFrames, 0)
    }

    func testInvalidRequestedFrameCountDoesNotAllowOneFrameCapture() {
        var coordinator = AvatarCaptureCoordinator(requiredFrames: 0)
        XCTAssertNil(coordinator.accept(ready))
        XCTAssertEqual(coordinator.accept(ready), .front)
    }
}
