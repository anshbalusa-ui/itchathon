#if DEBUG
import Foundation
import simd

struct MeasurementAvatarInput: Equatable, Sendable {
    let heightCM: Double
    let chestCM: Double
    let waistCM: Double
    let hipsCM: Double
    let shouldersCM: Double

    static let sampleA = try! MeasurementAvatarInput(heightCM: 180, chestCM: 96, waistCM: 80, hipsCM: 98, shouldersCM: 43)
    static let sampleB = try! MeasurementAvatarInput(heightCM: 170, chestCM: 110, waistCM: 100, hipsCM: 112, shouldersCM: 48)

    init(heightCM: Double, chestCM: Double, waistCM: Double, hipsCM: Double, shouldersCM: Double) throws {
        guard heightCM.isFinite, (140...210).contains(heightCM) else { throw MeasurementAvatarInputError.height }
        guard chestCM.isFinite, (60...150).contains(chestCM) else { throw MeasurementAvatarInputError.chest }
        guard waistCM.isFinite, (50...140).contains(waistCM) else { throw MeasurementAvatarInputError.waist }
        guard hipsCM.isFinite, (60...155).contains(hipsCM) else { throw MeasurementAvatarInputError.hips }
        guard shouldersCM.isFinite, (30...65).contains(shouldersCM) else { throw MeasurementAvatarInputError.shoulders }
        self.heightCM = heightCM
        self.chestCM = chestCM
        self.waistCM = waistCM
        self.hipsCM = hipsCM
        self.shouldersCM = shouldersCM
    }
}

enum MeasurementAvatarInputError: Error, Equatable, LocalizedError {
    case unsupportedMeasurements
    case height, chest, waist, hips, shoulders
    var errorDescription: String? {
        switch self {
        case .height: "Height must be 140–210 cm."
        case .chest: "Chest circumference must be 60–150 cm."
        case .waist: "Waist circumference must be 50–140 cm."
        case .hips: "Hip circumference must be 60–155 cm."
        case .shoulders: "Shoulder width must be 30–65 cm."
        case .unsupportedMeasurements: "These proportions are outside this generic demo. Adjust the values or use Sample A or B."
        }
    }
}

struct MeasurementAvatarResult: Sendable {
    let input: MeasurementAvatarInput
    let body: RendererMesh
    let shirt: RendererMesh
    let shorts: RendererMesh

    fileprivate init(input: MeasurementAvatarInput, body: RendererMesh, shirt: RendererMesh, shorts: RendererMesh) {
        self.input = input
        self.body = body
        self.shirt = shirt
        self.shorts = shorts
    }
}

protocol MeasurementAvatarGenerating: Sendable {
    func generate(_ input: MeasurementAvatarInput) async throws -> MeasurementAvatarResult
}


private struct MeasurementAvatarPreparedTemplate: Sendable {
    let bodyPoints: [SIMD3<Float>]
    let bodyIndices: [UInt16]
    /// Hip, waist and chest perimeters, then upper-torso width, in the refined source.
    let sectionBasis: SIMD4<Float>
    let bodyMinimumY: Float
    let bodyHeight: Float
    let shirt: RendererMesh
    let shorts: RendererMesh
}

actor MeasurementAvatarGenerator: MeasurementAvatarGenerating {
    static let shared = MeasurementAvatarGenerator()
    private var preparedTemplate: MeasurementAvatarPreparedTemplate?

    func generate(_ input: MeasurementAvatarInput) async throws -> MeasurementAvatarResult {
        try Task.checkCancellation()
        if preparedTemplate == nil {
            preparedTemplate = try MeasurementAvatarGeometry.prepare(from: HumanShowcaseAssets.load())
        }
        guard let prepared = preparedTemplate else { throw HumanShowcaseAssetFailure.rejectedPayload }
        // Actor isolation keeps all CPU work off the UI executor and serializes
        // requests; cancellation checkpoints bound discarded generation work.
        return try MeasurementAvatarGeometry.generate(input, from: prepared)
    }
}

private enum MeasurementAvatarGeometry {
    private static func cancellationRequested() -> Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }


    private struct ScaleKnot {
        let fraction: Float
        let scale: Float
    }
    private struct DeformationField {
        let sourceMinimumY: Float
        let sourceHeight: Float
        let targetHeight: Float
        let shoulderTranslation: Float
        let knots: [ScaleKnot]

        func scale(at fraction: Float) -> Float {
            guard let first = knots.first, let last = knots.last else { return 1 }
            if fraction <= first.fraction { return first.scale }
            if fraction >= last.fraction { return last.scale }
            for index in 0..<(knots.count - 1) {
                let lower = knots[index], upper = knots[index + 1]
                if fraction <= upper.fraction {
                    let t = (fraction - lower.fraction) / (upper.fraction - lower.fraction)
                    let smooth = t * t * (3 - 2 * t)
                    return lower.scale + (upper.scale - lower.scale) * smooth
                }
            }
            return 1
        }

        func transform(_ point: SIMD3<Float>) -> SIMD3<Float> {
            let fraction = (point.y - sourceMinimumY) / sourceHeight
            let factor = scale(at: fraction)
            let headBlend = min(max((fraction - 0.82) / 0.04, 0), 1)
            let shift = shoulderTranslation * (1 - headBlend * headBlend * (3 - 2 * headBlend))
            // This diagonal follows the pinned A-pose shoulder/arm boundary.
            // Outside it, move the arm as a whole: sampling torso scales along
            // the sloping arm otherwise creates artificial deltoid bulges.
            let start = max(0.08, 0.59 - 0.28 * point.y - 0.03)
            let end = max(start + 0.08, factor * start - shift + 0.08)
            let radius = abs(point.x)
            let blend = min(max((radius - start) / (end - start), 0), 1)
            let torsoWeight = 1 - blend * blend * (3 - 2 * blend)
            let depthScale = 1 + (factor - 1) * torsoWeight
            let mapped = mapRadius(radius, scale: factor, start: start, end: end, shift: shift)
            return SIMD3(point.x < 0 ? -mapped : mapped, fraction * targetHeight, point.z * depthScale)
        }

        private func mapRadius(_ radius: Float, scale: Float, start: Float, end: Float, shift: Float) -> Float {
            if radius <= start { return radius * scale }
            if radius >= end { return radius + shift }
            let width = end - start
            let lower = start * scale
            let upper = end + shift
            let secant = (upper - lower) / width
            var lowerSlope = scale
            var upperSlope: Float = 1
            let alpha = lowerSlope / secant
            let beta = upperSlope / secant
            let magnitude = alpha * alpha + beta * beta
            if magnitude > 9 {
                let limit = 3 / sqrt(magnitude)
                lowerSlope *= limit
                upperSlope *= limit
            }
            let t = (radius - start) / width
            let t2 = t * t
            let t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * lower
                + (t3 - 2 * t2 + t) * width * lowerSlope
                + (-2 * t3 + 3 * t2) * upper
                + (t3 - t2) * width * upperSlope
        }
    }

    static func prepare(from source: HumanShowcaseMeshes) throws -> MeasurementAvatarPreparedTemplate {
        var points = source.body.vertices.map(\.position)
        var indices = source.body.indices
        try SmoothMeshGeometry.subdivide(points: &points, indices: &indices)
        let bounds = points.reduce(into: (minimum: Float.greatestFiniteMagnitude, maximum: -Float.greatestFiniteMagnitude)) {
            $0.minimum = min($0.minimum, $1.y); $0.maximum = max($0.maximum, $1.y)
        }
        guard bounds.maximum > bounds.minimum, points.count < Int(UInt16.max) else {
            throw HumanShowcaseAssetFailure.rejectedPayload
        }
        let sourceHeight = bounds.maximum - bounds.minimum
        func sectionY(_ fraction: Float) -> Float { bounds.minimum + fraction * sourceHeight }
        let sectionBasis = SIMD4<Float>(
            try SmoothMeshGeometry.centralSection(points: points, indices: indices, y: sectionY(0.51)).perimeter,
            try SmoothMeshGeometry.centralSection(points: points, indices: indices, y: sectionY(0.57)).perimeter,
            try SmoothMeshGeometry.centralSection(points: points, indices: indices, y: sectionY(0.72)).perimeter,
            try SmoothMeshGeometry.centralSection(points: points, indices: indices, y: sectionY(0.755)).width
        )
        return MeasurementAvatarPreparedTemplate(
            bodyPoints: points,
            bodyIndices: indices,
            sectionBasis: sectionBasis,
            bodyMinimumY: bounds.minimum,
            bodyHeight: bounds.maximum - bounds.minimum,
            shirt: source.shirt,
            shorts: source.shorts
        )
    }

    static func generate(_ input: MeasurementAvatarInput, from template: MeasurementAvatarPreparedTemplate) throws -> MeasurementAvatarResult {
        let field = try deformationField(input, template: template)
        let body = try transformedMesh(points: template.bodyPoints, indices: template.bodyIndices, field: field)
        let shirt = try transformedIllustration(template.shirt, field: field)
        let shorts = try transformedIllustration(template.shorts, field: field)
        return MeasurementAvatarResult(input: input, body: body, shirt: shirt, shorts: shorts)
    }

    private static func deformationField(
        _ input: MeasurementAvatarInput,
        template: MeasurementAvatarPreparedTemplate
    ) throws -> DeformationField {
        let scales = SIMD4<Float>(
            Float(input.hipsCM / 100) / template.sectionBasis.x,
            Float(input.waistCM / 100) / template.sectionBasis.y,
            Float(input.chestCM / 100) / template.sectionBasis.z,
            Float(input.shouldersCM / 100) / template.sectionBasis.w
        )
        guard scales.x.isFinite, scales.y.isFinite, scales.z.isFinite, scales.w.isFinite,
              (0.55...2.1).contains(scales.x), (0.55...2.1).contains(scales.y),
              (0.55...2.1).contains(scales.z), (0.55...2.1).contains(scales.w) else {
            throw MeasurementAvatarInputError.unsupportedMeasurements
        }
        return DeformationField(
            sourceMinimumY: template.bodyMinimumY,
            sourceHeight: template.bodyHeight,
            targetHeight: Float(input.heightCM / 100),
            shoulderTranslation: (Float(input.shouldersCM / 100) - template.sectionBasis.w) * 0.5,
            knots: [
                ScaleKnot(fraction: 0, scale: 1),
                ScaleKnot(fraction: 0.35, scale: 1),
                ScaleKnot(fraction: 0.51, scale: scales.x),
                ScaleKnot(fraction: 0.57, scale: scales.y),
                ScaleKnot(fraction: 0.72, scale: scales.z),
                ScaleKnot(fraction: 0.755, scale: scales.w),
                ScaleKnot(fraction: 0.86, scale: 1),
                ScaleKnot(fraction: 1, scale: 1)
            ]
        )
    }

    private static func transformedMesh(
        points: [SIMD3<Float>],
        indices: [UInt16],
        field: DeformationField
    ) throws -> RendererMesh {
        var transformed: [SIMD3<Float>] = []
        transformed.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            if index.isMultiple(of: 1024), cancellationRequested() { throw CancellationError() }
            transformed.append(field.transform(point))
        }
        return mesh(points: transformed, indices: indices)
    }

    private static func transformedIllustration(_ source: RendererMesh, field: DeformationField) throws -> RendererMesh {
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(source.vertices.count)
        for (index, vertex) in source.vertices.enumerated() {
            if index.isMultiple(of: 1024), cancellationRequested() { throw CancellationError() }
            points.append(field.transform(vertex.position))
        }
        return mesh(points: points, indices: source.indices)
    }

    private static func mesh(points: [SIMD3<Float>], indices: [UInt16]) -> RendererMesh {
        let normals = smoothNormals(points: points, indices: indices)
        var vertices: [RendererVertex] = []
        vertices.reserveCapacity(points.count)
        for index in points.indices {
            vertices.append(RendererVertex(position: points[index], normal: normals[index]))
        }
        let bounds = points.reduce(into: (
            minimum: SIMD3<Float>(repeating: .greatestFiniteMagnitude),
            maximum: SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        )) {
            $0.minimum = simd.min($0.minimum, $1); $0.maximum = simd.max($0.maximum, $1)
        }
        return RendererMesh(vertices: vertices, indices: indices, minimum: bounds.minimum, maximum: bounds.maximum, sampleClearance: nil)
    }

    private static func smoothNormals(points: [SIMD3<Float>], indices: [UInt16]) -> [SIMD3<Float>] {
        var sums = Array(repeating: SIMD3<Float>.zero, count: points.count)
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            let normal = simd_cross(points[b] - points[a], points[c] - points[a])
            sums[a] += normal
            sums[b] += normal
            sums[c] += normal
        }
        return sums.map { simd_length_squared($0) > 1e-14 ? simd_normalize($0) : SIMD3(0,1,0) }
    }
}
#endif
