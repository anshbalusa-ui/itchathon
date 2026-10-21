#if DEBUG
import simd

struct RendererVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct RendererMesh {
    let vertices: [RendererVertex]
    let indices: [UInt16]
    var minimum: SIMD3<Float>
    var maximum: SIMD3<Float>
}

enum RendererProceduralAssets {
    static func mannequin() -> RendererMesh {
        var builder = MeshBuilder()
        let sphere = makeSphere(stacks: 12, segments: 16)

        builder.addEllipsoid(sphere, center: SIMD3(0, 1.62, 0), scale: SIMD3(0.097, 0.129, 0.094))
        builder.addBox(center: SIMD3(0, 1.48, 0), size: SIMD3(0.12, 0.13, 0.12))
        builder.addEllipsoid(sphere, center: SIMD3(0, 1.12, 0), scale: SIMD3(0.21, 0.275, 0.11))
        builder.addBox(center: SIMD3(0, 0.89, 0), size: SIMD3(0.28, 0.18, 0.18))
        builder.addBox(center: SIMD3(0, 0.745, 0), size: SIMD3(0.35, 0.23, 0.205))
        builder.addEllipsoid(sphere, center: SIMD3(-0.285, 1.12, 0), scale: SIMD3(0.057, 0.192, 0.062))
        builder.addEllipsoid(sphere, center: SIMD3(0.285, 1.12, 0), scale: SIMD3(0.057, 0.192, 0.062))
        builder.addBox(center: SIMD3(-0.094, 0.40, 0), size: SIMD3(0.145, 0.61, 0.16))
        builder.addBox(center: SIMD3(0.094, 0.40, 0), size: SIMD3(0.145, 0.61, 0.16))
        builder.addBox(center: SIMD3(-0.094, 0.045, 0.065), size: SIMD3(0.14, 0.09, 0.255))
        builder.addBox(center: SIMD3(0.094, 0.045, 0.065), size: SIMD3(0.14, 0.09, 0.255))
        return builder.finish()
    }

    static func garment() -> RendererMesh {
        var builder = MeshBuilder()
        // Uncapped elliptical rings form an open neckline and hem.
        let profile: [(y: Float, x: Float, z: Float)] = [
            (0.965, 0.218, 0.12), (1.00, 0.224, 0.125),
            (1.20, 0.226, 0.124), (1.32, 0.245, 0.13),
            (1.385, 0.09, 0.078)
        ]
        builder.addOpenShell(profile, centerZ: 0.006, segments: 24)
        builder.addBox(center: SIMD3(-0.30, 1.305, 0.005), size: SIMD3(0.15, 0.19, 0.225))
        builder.addBox(center: SIMD3(0.30, 1.305, 0.005), size: SIMD3(0.15, 0.19, 0.225))
        // Raised, open collar accent; it intentionally shares the garment tint.
        builder.addOpenShell([
            (1.355, 0.092, 0.079), (1.39, 0.105, 0.09), (1.415, 0.095, 0.082)
        ], centerZ: 0.006, segments: 24)
        return builder.finish()
    }

    static func color(for material: RendererMaterial) -> SIMD4<Float> {
        switch material {
        case .navy: return SIMD4(0.12, 0.22, 0.42, 1)
        case .stone: return SIMD4(0.55, 0.52, 0.46, 1)
        case .sage: return SIMD4(0.25, 0.40, 0.32, 1)
        }
    }

    private static func makeSphere(stacks: Int, segments: Int) -> RendererMesh {
        var vertices: [RendererVertex] = []
        var indices: [UInt16] = []
        vertices.append(RendererVertex(position: SIMD3(0, 1, 0), normal: SIMD3(0, 1, 0)))
        for stack in 1..<stacks {
            let latitude = Float.pi * 0.5 - Float(stack) * Float.pi / Float(stacks)
            let ringRadius = cos(latitude)
            for segment in 0..<segments {
                let angle = 2 * Float.pi * Float(segment) / Float(segments)
                let normal = SIMD3(ringRadius * cos(angle), sin(latitude), ringRadius * sin(angle))
                vertices.append(RendererVertex(position: normal, normal: normal))
            }
        }
        let bottom = UInt16(vertices.count)
        vertices.append(RendererVertex(position: SIMD3(0, -1, 0), normal: SIMD3(0, -1, 0)))
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices.append(contentsOf: [0, UInt16(1 + next), UInt16(1 + segment)])
        }
        for ring in 0..<(stacks - 2) {
            let lower = 1 + ring * segments
            let upper = lower + segments
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                let a = UInt16(lower + segment), b = UInt16(lower + next)
                let c = UInt16(upper + segment), d = UInt16(upper + next)
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        let lastRing = 1 + (stacks - 2) * segments
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            indices.append(contentsOf: [bottom, UInt16(lastRing + segment), UInt16(lastRing + next)])
        }
        return RendererMesh(vertices: vertices, indices: indices, minimum: SIMD3(repeating: -1), maximum: SIMD3(repeating: 1))
    }

    private struct MeshBuilder {
        var vertices: [RendererVertex] = []
        var indices: [UInt16] = []

        mutating func addEllipsoid(_ sphere: RendererMesh, center: SIMD3<Float>, scale: SIMD3<Float>) {
            let base = UInt16(vertices.count)
            for vertex in sphere.vertices {
                let normal = simd_normalize(SIMD3(vertex.normal.x / scale.x, vertex.normal.y / scale.y, vertex.normal.z / scale.z))
                vertices.append(RendererVertex(position: center + vertex.position * scale, normal: normal))
            }
            for index in sphere.indices { indices.append(base + index) }
        }

        mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>) {
            let h = size * 0.5
            let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
                (SIMD3(1, 0, 0), [SIMD3(h.x,-h.y,-h.z), SIMD3(h.x,h.y,-h.z), SIMD3(h.x,h.y,h.z), SIMD3(h.x,-h.y,h.z)]),
                (SIMD3(-1, 0, 0), [SIMD3(-h.x,-h.y,h.z), SIMD3(-h.x,h.y,h.z), SIMD3(-h.x,h.y,-h.z), SIMD3(-h.x,-h.y,-h.z)]),
                (SIMD3(0, 1, 0), [SIMD3(-h.x,h.y,-h.z), SIMD3(-h.x,h.y,h.z), SIMD3(h.x,h.y,h.z), SIMD3(h.x,h.y,-h.z)]),
                (SIMD3(0, -1, 0), [SIMD3(-h.x,-h.y,h.z), SIMD3(-h.x,-h.y,-h.z), SIMD3(h.x,-h.y,-h.z), SIMD3(h.x,-h.y,h.z)]),
                (SIMD3(0, 0, 1), [SIMD3(-h.x,-h.y,h.z), SIMD3(h.x,-h.y,h.z), SIMD3(h.x,h.y,h.z), SIMD3(-h.x,h.y,h.z)]),
                (SIMD3(0, 0, -1), [SIMD3(h.x,-h.y,-h.z), SIMD3(-h.x,-h.y,-h.z), SIMD3(-h.x,h.y,-h.z), SIMD3(h.x,h.y,-h.z)])
            ]
            for (normal, corners) in faces {
                let base = UInt16(vertices.count)
                for point in corners { vertices.append(RendererVertex(position: center + point, normal: normal)) }
                indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            }
        }

        mutating func addOpenShell(_ profile: [(y: Float, x: Float, z: Float)], centerZ: Float, segments: Int) {
            let base = UInt16(vertices.count)
            for (ring, row) in profile.enumerated() {
                let previous = profile[max(0, ring - 1)]
                let next = profile[min(profile.count - 1, ring + 1)]
                let dy = next.y - previous.y
                let slopeX = dy == 0 ? 0 : (next.x - previous.x) / dy
                let slopeZ = dy == 0 ? 0 : (next.z - previous.z) / dy
                for segment in 0..<segments {
                    let angle = 2 * Float.pi * Float(segment) / Float(segments)
                    let x = cos(angle), z = sin(angle)
                    let normal = simd_normalize(SIMD3(x / row.x, -(slopeX * x * x / row.x + slopeZ * z * z / row.z), z / row.z))
                    vertices.append(RendererVertex(position: SIMD3(row.x * x, row.y, centerZ + row.z * z), normal: normal))
                }
            }
            for ring in 0..<(profile.count - 1) {
                for segment in 0..<segments {
                    let next = (segment + 1) % segments
                    let lower = base + UInt16(ring * segments + segment)
                    let lowerNext = base + UInt16(ring * segments + next)
                    let upper = lower + UInt16(segments), upperNext = lowerNext + UInt16(segments)
                    // With the chosen angle convention this winding faces outward.
                    indices.append(contentsOf: [lower, upper, lowerNext, lowerNext, upper, upperNext])
                }
            }
        }

        func finish() -> RendererMesh {
            guard let first = vertices.first?.position else {
                return RendererMesh(vertices: vertices, indices: indices, minimum: .zero, maximum: .zero)
            }
            var minimum = first
            var maximum = first
            for vertex in vertices.dropFirst() {
                minimum = simd_min(minimum, vertex.position)
                maximum = simd_max(maximum, vertex.position)
            }
            return RendererMesh(vertices: vertices, indices: indices, minimum: minimum, maximum: maximum)
        }
    }
}
#endif
