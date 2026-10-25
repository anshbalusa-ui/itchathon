#if DEBUG
import XCTest
@testable import FitCheck

final class ReplayCameraMathTests: XCTestCase {
    private let calibration = ReplayCalibration(imageWidth: 320, imageHeight: 240, fx: 260, fy: 290, cx: 160, cy: 120)
    private let pose = ReplayPose(translation: SIMD3(1, 2, 3), right: SIMD3(1, 0, 0),
                                  down: SIMD3(0, -1, 0), forward: SIMD3(0, 0, -1))

    func testIndependentAnalyticPixelCenterUnprojectionAndProjectionRoundTrip() throws {
        let point = try ReplayCameraMath.cameraPoint(pixelCenter: SIMD2(64.5, 48.5), depth: 2,
            calibration: calibration, rasterWidth: 128, rasterHeight: 96)
        XCTAssertEqual(point.x, ((64.5 / 128 * 320) - 160) / 260 * 2, accuracy: 1e-12)
        XCTAssertEqual(point.y, ((48.5 / 96 * 240) - 120) / 290 * 2, accuracy: 1e-12)
        XCTAssertEqual(point.z, 2, accuracy: 1e-12)
        let world = try ReplayCameraMath.worldPoint(point, pose: pose)
        XCTAssertEqual(world.x, 1 + point.x, accuracy: 1e-12)
        XCTAssertEqual(world.y, 2 - point.y, accuracy: 1e-12)
        XCTAssertEqual(world.z, 3 - point.z, accuracy: 1e-12)
        let roundTrip = try ReplayCameraMath.cameraPoint(fromWorld: world, pose: pose)
        XCTAssertEqual(roundTrip.x, point.x, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.y, point.y, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.z, point.z, accuracy: 1e-12)
        let depth = ReplayRaster(width: 128, height: 96, bytesPerRow: 512, bytes: Data())
        let frame = ReplayFrame(captureID: "test", frameID: "front", sequence: 1, timestamp: 1,
            view: .front, calibration: calibration, pose: pose, depth: depth)
        let projected = try ReplayCameraMath.project(worldPoint: world, frame: frame)
        XCTAssertEqual(projected.x, 64.5, accuracy: 1e-12)
        XCTAssertEqual(projected.y, 48.5, accuracy: 1e-12)
    }
    func testSideOpticalBasisRotatesIntoCommonWorld() throws {
        let side = ReplayPose(translation: SIMD3(2, 0.9, 0), right: SIMD3(0, 0, -1),
                              down: SIMD3(0, -1, 0), forward: SIMD3(-1, 0, 0))
        let world = try ReplayCameraMath.worldPoint(SIMD3(0.1, 0.2, 2), pose: side)
        XCTAssertEqual(world.x, 0, accuracy: 1e-12)
        XCTAssertEqual(world.y, 0.7, accuracy: 1e-12)
        XCTAssertEqual(world.z, -0.1, accuracy: 1e-12)
        let camera = try ReplayCameraMath.cameraPoint(fromWorld: world, pose: side)
        XCTAssertEqual(camera.x, 0.1, accuracy: 1e-12)
        XCTAssertEqual(camera.y, 0.2, accuracy: 1e-12)
        XCTAssertEqual(camera.z, 2, accuracy: 1e-12)
    }


    func testRayDistanceAndOpticalAxisDepthHaveExplicitDifferentMeaning() throws {
        let center = SIMD2(96.5, 20.5)
        let optical = try ReplayCameraMath.cameraPoint(pixelCenter: center, depth: 2, calibration: calibration,
            rasterWidth: 128, rasterHeight: 96, semantics: .opticalAxis)
        let ray = try ReplayCameraMath.cameraPoint(pixelCenter: center, depth: 2, calibration: calibration,
            rasterWidth: 128, rasterHeight: 96, semantics: .euclideanRayDistance)
        XCTAssertEqual(optical.z, 2, accuracy: 1e-12)
        XCTAssertEqual(sqrt(ray.x * ray.x + ray.y * ray.y + ray.z * ray.z), 2, accuracy: 1e-12)
        XCTAssertGreaterThan(optical.z, ray.z)
        XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: center, depth: 2, calibration: calibration,
            rasterWidth: 128, rasterHeight: 96, semantics: .unknown)) { XCTAssertEqual($0 as? ReplayFailure, .unsupportedConvention) }
    }

    func testFourRasterRotationsUndoStoredCenterCoordinates() throws {
        let nativeCenter = SIMD2(40.5, 20.5)
        let expected = SIMD3(((nativeCenter.x / 128 * 320) - 160) / 320 * 2,
                             ((nativeCenter.y / 96 * 240) - 120) / 240 * 2, 2.0)
        for (rotation, center) in [(ReplayRotation.up, SIMD2(40.5, 20.5)),
                                   (.right, SIMD2(75.5, 40.5)),
                                   (.down, SIMD2(87.5, 75.5)),
                                   (.left, SIMD2(20.5, 87.5))] {
            let width = rotation == .right || rotation == .left ? 96 : 128
            let height = rotation == .right || rotation == .left ? 128 : 96
            let c = ReplayCalibration(imageWidth: 320, imageHeight: 240, fx: 320, fy: 240, cx: 160, cy: 120)
            let point = try ReplayCameraMath.cameraPoint(pixelCenter: center, depth: 2, calibration: c,
                rasterWidth: width, rasterHeight: height, rotation: rotation)
            XCTAssertEqual(point.x, expected.x, accuracy: 1e-12)
            XCTAssertEqual(point.y, expected.y, accuracy: 1e-12)
            XCTAssertEqual(point.z, expected.z, accuracy: 1e-12)
            let raster = ReplayRaster(width: width, height: height, bytesPerRow: 0, bytes: Data())
            let frame = ReplayFrame(captureID: "rotation-test", frameID: "front", sequence: 1, timestamp: 1,
                view: .front, calibration: c, pose: pose, rotation: rotation, depth: raster)
            let world = try ReplayCameraMath.worldPoint(point, pose: pose)
            let projected = try ReplayCameraMath.project(worldPoint: world, frame: frame)
            XCTAssertEqual(projected.x, center.x, accuracy: 1e-12)
            XCTAssertEqual(projected.y, center.y, accuracy: 1e-12)
        }
        XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: SIMD2(1, 1), depth: 1,
            calibration: calibration, rasterWidth: 2, rasterHeight: 2, rotation: .unsupported)) {
            XCTAssertEqual($0 as? ReplayFailure, .unsupportedRotation)
        }
    }

    func testExplicitIntrinsicsOriginConversionIsHalfPixelEquivalent() throws {
        let corner = ReplayCalibration(imageWidth: 320, imageHeight: 240, fx: 260, fy: 290, cx: 160, cy: 120, origin: .rasterCorner)
        let sdk = ReplayCalibration(imageWidth: 320, imageHeight: 240, fx: 260, fy: 290, cx: 159.5, cy: 119.5, origin: .upperLeftPixelCenter)
        let args = (SIMD2(23.5, 77.5), 1.7, 128, 96)
        let a = try ReplayCameraMath.cameraPoint(pixelCenter: args.0, depth: args.1, calibration: corner,
            rasterWidth: args.2, rasterHeight: args.3)
        let b = try ReplayCameraMath.cameraPoint(pixelCenter: args.0, depth: args.1, calibration: sdk,
            rasterWidth: args.2, rasterHeight: args.3)
        XCTAssertEqual(a.x, b.x, accuracy: 1e-12)
        XCTAssertEqual(a.y, b.y, accuracy: 1e-12)
        XCTAssertEqual(a.z, b.z, accuracy: 1e-12)
        var unknown = corner; unknown.origin = .unknown
        XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: args.0, depth: args.1, calibration: unknown,
            rasterWidth: args.2, rasterHeight: args.3)) { XCTAssertEqual($0 as? ReplayFailure, .invalidCalibration) }
    }

    func testInvalidPoseCalibrationDepthAndPixelAreRejected() throws {
        var reflected = pose; reflected.forward = SIMD3(0, 0, 1)
        XCTAssertThrowsError(try ReplayCameraMath.worldPoint(.zero, pose: reflected)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var wrongDirection = pose; wrongDirection.direction = .worldToOptical
        XCTAssertThrowsError(try ReplayCameraMath.validate(wrongDirection)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var scaled = pose; scaled.scale = 0.01
        XCTAssertThrowsError(try ReplayCameraMath.validate(scaled)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var reflectedTag = pose; reflectedTag.handedness = .reflected
        XCTAssertThrowsError(try ReplayCameraMath.validate(reflectedTag)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var nonOrthonormal = pose; nonOrthonormal.right = SIMD3(0.999, 0.001, 0)
        XCTAssertThrowsError(try ReplayCameraMath.validate(nonOrthonormal)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var nonFinite = pose; nonFinite.translation.z = .infinity
        XCTAssertThrowsError(try ReplayCameraMath.validate(nonFinite)) { XCTAssertEqual($0 as? ReplayFailure, .invalidPose) }
        var invalidCalibration = calibration; invalidCalibration.fx = .infinity
        XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: SIMD2(1, 1), depth: 1,
            calibration: invalidCalibration, rasterWidth: 128, rasterHeight: 96)) { XCTAssertEqual($0 as? ReplayFailure, .invalidCalibration) }
        for depth in [Double.nan, 0, 5] {
            XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: SIMD2(1, 1), depth: depth,
                calibration: calibration, rasterWidth: 128, rasterHeight: 96)) { XCTAssertEqual($0 as? ReplayFailure, .invalidDepth) }
        }
        XCTAssertThrowsError(try ReplayCameraMath.cameraPoint(pixelCenter: SIMD2(-0.1, 1), depth: 1,
            calibration: calibration, rasterWidth: 128, rasterHeight: 96)) { XCTAssertEqual($0 as? ReplayFailure, .invalidLayout) }
    }
}
#endif
