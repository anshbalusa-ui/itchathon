#if DEBUG
import CoreVideo
import XCTest
@testable import FitCheck

@MainActor
final class AvatarScannerLifecycleTests: XCTestCase {
    func testRepeatedPreviewAppearanceDoesNotAutomaticallyResumeInterruptedAttempt() {
        let camera = SyntheticCamera(permission: .authorized)
        let model = AvatarScannerModel(processor: SuspendedAnalysis())
        model.attach(camera)
        let controller = AvatarGuidedCaptureController()
        controller.onReady = { model.start() }
        controller.loadViewIfNeeded()
        controller.viewDidAppear(false)
        XCTAssertEqual(model.phase, .scanning(.front))
        model.suspend()
        controller.viewDidAppear(false)
        XCTAssertEqual(model.phase, .retryRequired(.backgrounded))
        XCTAssertFalse(camera.running)
        model.detach()
    }

    func testCancelledPermissionReplyCannotStartCameraOrAffectRetry() {
        let camera = SyntheticCamera(permission: .notDetermined)
        let model = AvatarScannerModel(processor: SuspendedAnalysis())
        model.attach(camera)
        model.start()
        XCTAssertEqual(model.phase, .requestingPermission)
        let reply = camera.permissionReply!
        model.cancel()
        reply(true)
        XCTAssertEqual(model.phase, .cancelled)
        XCTAssertFalse(camera.running)

        camera.permission = .authorized
        model.start()
        XCTAssertEqual(model.phase, .scanning(.front))
        reply(false)
        XCTAssertEqual(model.phase, .scanning(.front))
        XCTAssertTrue(camera.running)
        model.detach()
        XCTAssertFalse(camera.running)
    }

    func testBackgroundPermissionReplyCannotResumeWithoutExplicitRetry() {
        let camera = SyntheticCamera(permission: .notDetermined)
        let model = AvatarScannerModel(processor: SuspendedAnalysis())
        model.attach(camera)
        model.start()
        model.suspend()
        camera.permissionReply?(true)
        XCTAssertEqual(model.phase, .retryRequired(.backgrounded))
        XCTAssertFalse(camera.running)
        camera.permission = .authorized
        model.start()
        XCTAssertEqual(model.phase, .scanning(.front))
        XCTAssertTrue(camera.running)
        model.detach()
    }

    func testStaleAnalysisAfterRetryCannotPublishGuidanceOrAcceptNewFrameEarly() throws {
        let camera = SyntheticCamera(permission: .authorized)
        let processor = SuspendedAnalysis()
        let model = AvatarScannerModel(processor: processor, now: { 11 })
        model.attach(camera)
        model.start()
        camera.onFrame?(try input(timestamp: 10))
        let oldCompletion = processor.completions[0]
        model.cancel()
        model.start()
        camera.onFrame?(try input(timestamp: 10.5))
        XCTAssertEqual(processor.completions.count, 1, "Old physical work must finish before another frame is retained")
        oldCompletion(AppleScanAnalysis(
            assessment: ScanFrameAssessment(timestamp: 10, rejection: .missingPerson, view: .unverified, anchor: nil),
            metadata: nil, planes: nil
        ))
        XCTAssertEqual(model.phase, .scanning(.front))
        XCTAssertNil(model.guidance)
        XCTAssertNil(model.evidence)
        camera.onFrame?(try input(timestamp: 11))
        XCTAssertEqual(processor.completions.count, 2)
        processor.completions[1](AppleScanAnalysis(
            assessment: ScanFrameAssessment(timestamp: 11, rejection: .invalidAlignment, view: .unverified, anchor: nil),
            metadata: nil, planes: nil
        ))
        XCTAssertEqual(model.guidance, .invalidAlignment)
        XCTAssertEqual(model.phase, .scanning(.front))
        model.detach()
    }

    func testUnsupportedAndDeniedDevicesNeverBecomeActive() {
        let camera = SyntheticCamera(permission: .authorized)
        camera.supportsSceneDepth = false
        let model = AvatarScannerModel(processor: SuspendedAnalysis())
        model.attach(camera)
        model.start()
        XCTAssertEqual(model.phase, .unavailable(.unsupportedDevice))
        XCTAssertFalse(camera.running)
        camera.supportsSceneDepth = true
        camera.permission = .denied
        model.start()
        XCTAssertEqual(model.phase, .unavailable(.cameraDenied))
        XCTAssertFalse(camera.running)
        model.detach()
    }

    private func input(timestamp: Double) throws -> AppleScanFrameInput {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 32, 24, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        return AppleScanFrameInput(
            timestamp: timestamp, image: try XCTUnwrap(buffer), depth: nil, confidence: nil,
            imageRotation: .right, calibration: ScanCameraCalibration(fx: 32, fy: 32, cx: 16, cy: 12),
            cameraPosition: ScanVector(x: 0, y: 0, z: 0), cameraForward: ScanVector(x: 0, y: 0, z: -1), trackingNormal: true
        )
    }
}

@MainActor
private final class SyntheticCamera: ScanCameraDriving {
    var supportsSceneDepth = true
    var permission: ScanCameraPermission
    var onFrame: ((AppleScanFrameInput) -> Void)?
    var onInterruption: ((ScanInterruption) -> Void)?
    var permissionReply: (@MainActor (Bool) -> Void)?
    private(set) var running = false
    init(permission: ScanCameraPermission) { self.permission = permission }
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) { permissionReply = completion }
    func run() { running = true }
    func pause() { running = false }
}

@MainActor
private final class SuspendedAnalysis: ScanFrameProcessing {
    var completions: [@MainActor (AppleScanAnalysis?) -> Void] = []
    func process(_ input: AppleScanFrameInput, generation: UInt64, completion: @escaping @MainActor (AppleScanAnalysis?) -> Void) {
        completions.append(completion)
    }
    func releaseRequests() { /* There are no Vision requests in this controlled test worker. */ }
}
#endif
