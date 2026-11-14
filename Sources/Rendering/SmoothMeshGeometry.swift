import Foundation
import simd

struct SmoothMeshSection {
    let perimeter: Float
    let minimumX: Float
    let maximumX: Float
    var centerX: Float { (minimumX + maximumX) * 0.5 }
    var width: Float { maximumX - minimumX }
}

enum SmoothMeshGeometry {
    private struct PointKey: Hashable {
        let x: Int
        let z: Int
        init(_ point: SIMD2<Float>) {
            x = Int((point.x * 100_000).rounded())
            z = Int((point.y * 100_000).rounded())
        }
    }

    private static func cancellationRequested() -> Bool {
        withUnsafeCurrentTask { $0?.isCancelled ?? false }
    }

    static func subdivide(points: inout [SIMD3<Float>], indices: inout [UInt16], allowBoundary: Bool = false) throws {
        var edgeOpposites: [UInt64: [Int]] = [:]
        var neighbors = Array(repeating: Set<Int>(), count: points.count)
        func key(_ a: Int, _ b: Int) -> UInt64 {
            UInt64(UInt32(min(a, b))) << 32 | UInt64(UInt32(max(a, b)))
        }
        func addEdge(_ a: Int, _ b: Int, opposite: Int) {
            edgeOpposites[key(a, b), default: []].append(opposite)
            neighbors[a].insert(b)
            neighbors[b].insert(a)
        }
        for offset in stride(from: 0, to: indices.count, by: 3) {
            if offset.isMultiple(of: 3072), cancellationRequested() { throw CancellationError() }
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            addEdge(a, b, opposite: c)
            addEdge(b, c, opposite: a)
            addEdge(c, a, opposite: b)
        }
        guard points.count + edgeOpposites.count < Int(UInt16.max),
              edgeOpposites.values.allSatisfy({ $0.count == 2 || (allowBoundary && $0.count == 1) }) else {
            throw HumanShowcaseAssetFailure.rejectedPayload
        }
        var boundaryNeighbors: [[Int]] = allowBoundary ? Array(repeating: [], count: points.count) : []
        if allowBoundary {
            for (edge, opposites) in edgeOpposites where opposites.count == 1 {
                let a = Int(edge >> 32), b = Int(UInt32(truncatingIfNeeded: edge))
                boundaryNeighbors[a].append(b)
                boundaryNeighbors[b].append(a)
            }
            guard boundaryNeighbors.allSatisfy({ $0.isEmpty || $0.count == 2 }) else {
                throw HumanShowcaseAssetFailure.rejectedPayload
            }
        }
        var updated = points
        for i in points.indices where !neighbors[i].isEmpty {
            if i.isMultiple(of: 1024), cancellationRequested() { throw CancellationError() }
            if allowBoundary && !boundaryNeighbors[i].isEmpty {
                let boundary = boundaryNeighbors[i].sorted()
                updated[i] = points[i] * 0.75 + (points[boundary[0]] + points[boundary[1]]) * 0.125
                continue
            }
            let orderedNeighbors = neighbors[i].sorted()
            var sum = SIMD3<Float>.zero
            for neighbor in orderedNeighbors { sum += points[neighbor] }
            let count = Float(orderedNeighbors.count)
            let beta: Float = orderedNeighbors.count == 3 ? 3 / 16 : 3 / (8 * count)
            updated[i] = points[i] * (1 - beta * count) + sum * beta
        }
        var edgeVertices: [UInt64: Int] = [:]
        edgeVertices.reserveCapacity(edgeOpposites.count)
        for (index, edge) in edgeOpposites.keys.sorted().enumerated() {
            if index.isMultiple(of: 1024), cancellationRequested() { throw CancellationError() }
            let opposites = edgeOpposites[edge]!
            let a = Int(edge >> 32), b = Int(UInt32(truncatingIfNeeded: edge))
            edgeVertices[edge] = updated.count
            if opposites.count == 1 {
                updated.append((points[a] + points[b]) * 0.5)
            } else {
                updated.append((points[a] + points[b]) * 0.375 + (points[opposites[0]] + points[opposites[1]]) * 0.125)
            }
        }
        var refined: [UInt16] = []
        refined.reserveCapacity(indices.count * 4)
        for offset in stride(from: 0, to: indices.count, by: 3) {
            if offset.isMultiple(of: 3072), cancellationRequested() { throw CancellationError() }
            let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
            let ab = UInt16(edgeVertices[key(a, b)]!)
            let bc = UInt16(edgeVertices[key(b, c)]!)
            let ca = UInt16(edgeVertices[key(c, a)]!)
            refined.append(UInt16(a)); refined.append(ab); refined.append(ca)
            refined.append(ab); refined.append(UInt16(b)); refined.append(bc)
            refined.append(ca); refined.append(bc); refined.append(UInt16(c))
            refined.append(ab); refined.append(bc); refined.append(ca)
        }
        points = updated
        indices = refined
    }

    static func centralSection(points: [SIMD3<Float>], indices: [UInt16], y: Float) throws -> SmoothMeshSection {
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        segments.reserveCapacity(256)
        for offset in stride(from: 0, to: indices.count, by: 3) {
            if offset.isMultiple(of: 3072), cancellationRequested() { throw CancellationError() }
            let p0 = points[Int(indices[offset])], p1 = points[Int(indices[offset + 1])], p2 = points[Int(indices[offset + 2])]
            var first = SIMD2<Float>.zero
            var second = SIMD2<Float>.zero
            var count = 0
            func intersect(_ p: SIMD3<Float>, _ q: SIMD3<Float>) {
                guard ((p.y < y && q.y >= y) || (q.y < y && p.y >= y)) else { return }
                let t = (y - p.y) / (q.y - p.y)
                let point = SIMD2(p.x + t * (q.x - p.x), p.z + t * (q.z - p.z))
                if count == 0 { first = point } else { second = point }
                count += 1
            }
            intersect(p0, p1); intersect(p1, p2); intersect(p2, p0)
            if count == 2 { segments.append((first, second)) }
        }
        var endpoints: [PointKey: SIMD2<Float>] = [:]
        var incident: [PointKey: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            let a = PointKey(segment.0), b = PointKey(segment.1)
            endpoints[a] = segment.0; endpoints[b] = segment.1
            incident[a, default: []].append(index); incident[b, default: []].append(index)
        }
        var used = Set<Int>()
        var loops: [SmoothMeshSection] = []
        for seed in segments.indices where !used.contains(seed) {
            var pending = [PointKey(segments[seed].0)]
            var visited = Set<PointKey>()
            var perimeter: Float = 0
            var minimumX = Float.greatestFiniteMagnitude
            var maximumX = -Float.greatestFiniteMagnitude
            while let point = pending.popLast() {
                guard visited.insert(point).inserted else { continue }
                if let value = endpoints[point] { minimumX = min(minimumX, value.x); maximumX = max(maximumX, value.x) }
                for edge in incident[point] ?? [] where used.insert(edge).inserted {
                    let segment = segments[edge]
                    perimeter += simd_distance(segment.0, segment.1)
                    pending.append(PointKey(segment.0)); pending.append(PointKey(segment.1))
                }
            }
            loops.append(SmoothMeshSection(perimeter: perimeter, minimumX: minimumX, maximumX: maximumX))
        }
        guard let section = loops.filter({ abs($0.centerX) < 0.12 }).max(by: { $0.perimeter < $1.perimeter }) else {
            throw HumanShowcaseAssetFailure.rejectedPayload
        }
        return section
    }
}
