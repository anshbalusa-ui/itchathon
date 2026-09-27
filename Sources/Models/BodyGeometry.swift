import Foundation

enum BodyGeometry {
    enum GeometryError: Error, Equatable {
        case invalidSpan
        case nonFiniteCircumference
    }

    static func circumference(width: Double, depth: Double) throws -> Double {
        guard width.isFinite, depth.isFinite, width > 0, depth > 0 else {
            throw GeometryError.invalidSpan
        }

        // Normalize before halving or adding so very large spans cannot overflow,
        // and very small valid spans do not underflow to zero.
        let scale = max(width, depth)
        let normalizedWidth = width / scale
        let normalizedDepth = depth / scale
        let sum = normalizedWidth + normalizedDepth
        let a = normalizedWidth / 2
        let b = normalizedDepth / 2
        let difference = a - b
        let ratio = difference / (a + b)
        let h = ratio * ratio
        let normalizedCircumference = Double.pi * sum / 2 * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
        let result = (scale * normalizedCircumference)

        guard result.isFinite, result > 0 else {
            throw GeometryError.nonFiniteCircumference
        }
        return result
    }
}
