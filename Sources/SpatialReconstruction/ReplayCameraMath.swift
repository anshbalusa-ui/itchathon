#if DEBUG
import Foundation

/// Bounded pinhole-camera transforms for owned, explicitly calibrated replay observations.
enum ReplayCameraMath {
    static func cameraPoint(pixelCenter: SIMD2<Double>, depth: Double, calibration: ReplayCalibration,
                           rasterWidth: Int, rasterHeight: Int, rotation: ReplayRotation = .up,
                           semantics: ReplayDepthSemantics = .opticalAxis) throws -> SIMD3<Double> {
        let projector = try prepare(calibration: calibration, rasterWidth: rasterWidth,
                                    rasterHeight: rasterHeight, rotation: rotation, semantics: semantics)
        return try projector.cameraPoint(pixelCenter: pixelCenter, depth: depth)
    }

    /// Validate invariant calibration once per raster, not again for every point.
    static func prepare(calibration: ReplayCalibration, rasterWidth: Int, rasterHeight: Int,
                        rotation: ReplayRotation, semantics: ReplayDepthSemantics) throws -> ReplayRayProjector {
        guard rasterWidth > 1, rasterHeight > 1,
              rasterWidth <= ReplayLimits.maximumRasterDimension, rasterHeight <= ReplayLimits.maximumRasterDimension,
              calibration.imageWidth > 1, calibration.imageHeight > 1,
              calibration.imageWidth <= 16_384, calibration.imageHeight <= 16_384,
              calibration.fx.isFinite, calibration.fy.isFinite, calibration.cx.isFinite, calibration.cy.isFinite,
              calibration.fx > 0, calibration.fy > 0, calibration.origin != .unknown else { throw ReplayFailure.invalidCalibration }
        let offset = calibration.origin == .upperLeftPixelCenter ? 0.5 : 0.0
        let cx = calibration.cx + offset, cy = calibration.cy + offset
        guard cx >= 0, cx < Double(calibration.imageWidth), cy >= 0, cy < Double(calibration.imageHeight) else {
            throw ReplayFailure.invalidCalibration
        }
        guard rotation != .unsupported else { throw ReplayFailure.unsupportedRotation }
        guard semantics != .unknown else { throw ReplayFailure.unsupportedConvention }
        return ReplayRayProjector(calibration: calibration, width: rasterWidth, height: rasterHeight,
                                  rotation: rotation, semantics: semantics)
    }

    static func worldPoint(_ point: SIMD3<Double>, pose: ReplayPose) throws -> SIMD3<Double> {
        try validate(pose)
        guard finite(point) else { throw ReplayFailure.invalidPose }
        let result = pose.translation + pose.right * point.x + pose.down * point.y + pose.forward * point.z
        guard finite(result) else { throw ReplayFailure.invalidPose }
        return result
    }

    static func cameraPoint(fromWorld point: SIMD3<Double>, pose: ReplayPose) throws -> SIMD3<Double> {
        try validate(pose)
        guard finite(point) else { throw ReplayFailure.invalidPose }
        let delta = point - pose.translation
        let result = SIMD3(dot(delta, pose.right), dot(delta, pose.down), dot(delta, pose.forward))
        guard finite(result) else { throw ReplayFailure.invalidPose }
        return result
    }

    static func project(worldPoint: SIMD3<Double>, frame: ReplayFrame) throws -> SIMD2<Double> {
        let p = try cameraPoint(fromWorld: worldPoint, pose: frame.pose)
        guard p.z > 0, p.z.isFinite else { throw ReplayFailure.invalidDepth }
        let c = frame.calibration
        guard c.imageWidth > 1, c.imageHeight > 1, c.imageWidth <= 16_384, c.imageHeight <= 16_384,
              c.fx.isFinite, c.fy.isFinite, c.cx.isFinite, c.cy.isFinite,
              c.fx > 0, c.fy > 0, c.origin != .unknown else { throw ReplayFailure.invalidCalibration }
        let offset = c.origin == .upperLeftPixelCenter ? 0.5 : 0.0
        guard (0..<Double(c.imageWidth)).contains(c.cx + offset),
              (0..<Double(c.imageHeight)).contains(c.cy + offset) else { throw ReplayFailure.invalidCalibration }
        guard let depth = frame.depth else { throw ReplayFailure.missingDepth }
        let width = depth.width
        let height = depth.height
        guard width > 1, height > 1, width <= ReplayLimits.maximumRasterDimension,
              height <= ReplayLimits.maximumRasterDimension else { throw ReplayFailure.invalidLayout }
        let u = c.fx * (p.x / p.z) + c.cx + offset
        let v = c.fy * (p.y / p.z) + c.cy + offset
        let native = SIMD2(u / Double(c.imageWidth), v / Double(c.imageHeight))
        let stored = try storedCenter(native, width: width, height: height, rotation: frame.rotation)
        guard stored.x.isFinite, stored.y.isFinite else { throw ReplayFailure.invalidDepth }
        return stored
    }

    static func validate(_ pose: ReplayPose) throws {
        guard pose.direction == .opticalToWorld, pose.handedness == .rightHanded,
              pose.referenceFrame == "synthetic-world-y-up-v1", pose.scale.isFinite, pose.scale == 1,
              finite(pose.translation), finite(pose.right), finite(pose.down), finite(pose.forward),
              finite(pose.homogeneousRow), pose.homogeneousRow == SIMD4(0, 0, 0, 1) else { throw ReplayFailure.invalidPose }
        guard abs(pose.translation.x) <= ReplayLimits.maximumCameraTranslation,
              abs(pose.translation.y) <= ReplayLimits.maximumCameraTranslation,
              abs(pose.translation.z) <= ReplayLimits.maximumCameraTranslation else { throw ReplayFailure.invalidPose }
        let tolerance = 1e-6
        guard abs(length(pose.right) - 1) <= tolerance, abs(length(pose.down) - 1) <= tolerance,
              abs(length(pose.forward) - 1) <= tolerance, abs(dot(pose.right, pose.down)) <= tolerance,
              abs(dot(pose.right, pose.forward)) <= tolerance, abs(dot(pose.down, pose.forward)) <= tolerance,
              dot(cross(pose.right, pose.down), pose.forward) >= 1 - tolerance else { throw ReplayFailure.invalidPose }
    }

    fileprivate static func unrotatedCenter(_ p: SIMD2<Double>, width: Int, height: Int, rotation: ReplayRotation) throws -> SIMD2<Double> {
        let x = p.x / Double(width), y = p.y / Double(height)
        switch rotation {
        case .up: return p
        case .right: return SIMD2(y * Double(height), (1 - x) * Double(width))
        case .down: return SIMD2((1 - x) * Double(width), (1 - y) * Double(height))
        case .left: return SIMD2((1 - y) * Double(height), x * Double(width))
        case .unsupported: throw ReplayFailure.unsupportedRotation
        }
    }
    private static func storedCenter(_ native: SIMD2<Double>, width: Int, height: Int, rotation: ReplayRotation) throws -> SIMD2<Double> {
        let x = native.x, y = native.y
        switch rotation {
        case .up: return SIMD2(x * Double(width), y * Double(height))
        case .right: return SIMD2((1 - y) * Double(width), x * Double(height))
        case .down: return SIMD2((1 - x) * Double(width), (1 - y) * Double(height))
        case .left: return SIMD2(y * Double(width), (1 - x) * Double(height))
        case .unsupported: throw ReplayFailure.unsupportedRotation
        }
    }
    private static func finite(_ v: SIMD3<Double>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
    private static func finite(_ v: SIMD4<Double>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite }
    private static func length(_ v: SIMD3<Double>) -> Double { sqrt(dot(v, v)) }
    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { a.x*b.x + a.y*b.y + a.z*b.z }
    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> { SIMD3(a.y*b.z-a.z*b.y, a.z*b.x-a.x*b.z, a.x*b.y-a.y*b.x) }
}

/// An immutable numerical projector, not a source-authorization capability.
struct ReplayRayProjector {
    private let width: Int
    private let height: Int
    private let rotation: ReplayRotation
    private let semantics: ReplayDepthSemantics
    private let xScale: Double
    private let yScale: Double
    private let xOffset: Double
    private let yOffset: Double

    fileprivate init(calibration: ReplayCalibration, width: Int, height: Int,
                     rotation: ReplayRotation, semantics: ReplayDepthSemantics) {
        self.width = width
        self.height = height
        self.rotation = rotation
        self.semantics = semantics
        let nativeWidth = rotation == .right || rotation == .left ? height : width
        let nativeHeight = rotation == .right || rotation == .left ? width : height
        let offset = calibration.origin == .upperLeftPixelCenter ? 0.5 : 0.0
        xScale = Double(calibration.imageWidth) / Double(nativeWidth) / calibration.fx
        yScale = Double(calibration.imageHeight) / Double(nativeHeight) / calibration.fy
        xOffset = -(calibration.cx + offset) / calibration.fx
        yOffset = -(calibration.cy + offset) / calibration.fy
    }

    func cameraPoint(pixelCenter: SIMD2<Double>, depth: Double) throws -> SIMD3<Double> {
        guard pixelCenter.x.isFinite, pixelCenter.y.isFinite,
              (0.5...(Double(width) - 0.5)).contains(pixelCenter.x),
              (0.5...(Double(height) - 0.5)).contains(pixelCenter.y) else { throw ReplayFailure.invalidLayout }
        guard depth.isFinite, (ReplayLimits.minimumDepth...ReplayLimits.maximumDepth).contains(depth) else { throw ReplayFailure.invalidDepth }
        let native = try ReplayCameraMath.unrotatedCenter(pixelCenter, width: width, height: height, rotation: rotation)
        var ray = SIMD3(native.x * xScale + xOffset, native.y * yScale + yOffset, 1)
        if semantics == .euclideanRayDistance { ray /= sqrt(ray.x * ray.x + ray.y * ray.y + 1) }
        let point = ray * depth
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw ReplayFailure.invalidDepth }
        return point
    }
}
#endif
