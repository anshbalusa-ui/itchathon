#if DEBUG
import Foundation

/// Pure open elliptical section loft shared by reviewed fixtures and replay-derived sections.
enum GeometrySectionLoft {
    static func generate(sections: [GeometrySectionInput], radialSegments: Int = 24,
                         angularIndices: [Int]? = nil,
                         cancellationCheck: () -> Bool = { false }) throws -> GeometryMesh {
        try GeometryKernel.preflight(sectionCount: sections.count, radialSegments: radialSegments)
        let radialCount = angularIndices?.count ?? radialSegments
        if let angularIndices {
            guard radialCount >= 8, radialCount <= radialSegments,
                  angularIndices.allSatisfy({ (0..<radialSegments).contains($0) }) else { throw GeometryFailure.resourceLimit }
            for index in 1..<angularIndices.count {
                guard (angularIndices[index] - angularIndices[index - 1] + radialSegments) % radialSegments == 1 else {
                    throw GeometryFailure.invalidDimensions
                }
            }
        }
        let closesRing = angularIndices == nil || radialCount == radialSegments
        var vertices: [GeometryVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(sections.count * radialCount)
        indices.reserveCapacity((sections.count - 1) * (radialCount - (closesRing ? 0 : 1)) * 6)
        for section in sections {
            try checkCancellation(cancellationCheck)
            for segment in 0..<radialCount {
                let theta: Float
                if let angularIndices {
                    theta = 2 * Float.pi * Float(angularIndices[segment]) / Float(radialSegments)
                } else {
                    theta = 2 * Float.pi * Float(segment) / Float(radialSegments)
                }
                vertices.append(GeometryVertex(
                    position: SIMD3<Float>(section.halfWidthMetres * cos(theta), section.heightMetres,
                                           section.halfDepthMetres * sin(theta)),
                    normal: .zero
                ))
            }
        }
        for ring in 0..<(sections.count - 1) {
            try checkCancellation(cancellationCheck)
            for segment in 0..<(radialCount - (closesRing ? 0 : 1)) {
                let next = (segment + 1) % radialCount
                let lower = ring * radialCount
                let upper = lower + radialCount
                indices.append(UInt16(lower + segment))
                indices.append(UInt16(upper + segment))
                indices.append(UInt16(lower + next))
                indices.append(UInt16(upper + segment))
                indices.append(UInt16(upper + next))
                indices.append(UInt16(lower + next))
            }
        }
        for offset in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            let ab = vertices[b].position - vertices[a].position
            let ac = vertices[c].position - vertices[a].position
            let normal = cross(ab, ac)
            guard length(normal) > 1e-8 else { throw GeometryFailure.invalidMesh }
            vertices[a].normal += normal
            vertices[b].normal += normal
            vertices[c].normal += normal
        }
        for index in vertices.indices {
            let magnitude = length(vertices[index].normal)
            guard magnitude.isFinite, magnitude > 0 else { throw GeometryFailure.invalidMesh }
            vertices[index].normal /= magnitude
        }
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
        for vertex in vertices {
            minimum = SIMD3<Float>(min(minimum.x, vertex.position.x), min(minimum.y, vertex.position.y), min(minimum.z, vertex.position.z))
            maximum = SIMD3<Float>(max(maximum.x, vertex.position.x), max(maximum.y, vertex.position.y), max(maximum.z, vertex.position.z))
        }
        let mesh = GeometryMesh(vertices: vertices, indices: indices, minimum: minimum, maximum: maximum)
        try mesh.validate()
        try checkCancellation(cancellationCheck)
        return mesh
    }
    private static func checkCancellation(_ check: () -> Bool) throws { if check() { throw GeometryFailure.cancelled } }
    private static func length(_ value: SIMD3<Float>) -> Float { sqrt(dot(value, value)) }
    private static func dot(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float { lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z }
    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}
#endif
