#if DEBUG
import XCTest
import simd
@testable import FitCheck

final class MeasurementAvatarGeometryTests: XCTestCase {
    private struct PositionKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
        init(_ position: SIMD3<Float>) {
            x = Int((position.x * 100_000).rounded())
            y = Int((position.y * 100_000).rounded())
            z = Int((position.z * 100_000).rounded())
        }
    }

    func testSamplesProduceDistinctBodyAndExactHeightAndSectionTargets() async throws {
        let generator = MeasurementAvatarGenerator()
        let a = try await generator.generate(.sampleA)
        let b = try await generator.generate(.sampleB)
        XCTAssertEqual(a.body.maximum.y - a.body.minimum.y, 1.8, accuracy: 0.003)
        XCTAssertEqual(b.body.maximum.y - b.body.minimum.y, 1.7, accuracy: 0.003)
        for (result, values) in [(a, [96.0, 80, 98]), (b, [110.0, 100, 112])] {
            let height = Float(result.input.heightCM / 100)
            for (fraction, expected) in zip([0.72, 0.57, 0.51], values) {
                let measured = perimeter(mesh: result.body, y: height * Float(fraction))
                XCTAssertEqual(measured, Float(expected / 100), accuracy: 0.025)
            }
        }
        XCTAssertEqual(sectionWidth(mesh: a.body, y: 1.8 * 0.755), 0.43, accuracy: 0.025)
        XCTAssertEqual(sectionWidth(mesh: b.body, y: 1.7 * 0.755), 0.48, accuracy: 0.025)
        XCTAssertGreaterThan(sectionLoops(mesh: a.body, y: 1.8 * 0.755).count, 1)
        XCTAssertNotEqual(a.body.vertices.map(\.position), b.body.vertices.map(\.position))
        XCTAssertNil(a.body.sampleClearance)
        XCTAssertNil(a.shirt.sampleClearance)
        XCTAssertNil(a.shorts.sampleClearance)
    }
    func testGarmentsFollowHeightAndLocalTorsoHipFields() async throws {
        let generator = MeasurementAvatarGenerator()
        let a = try await generator.generate(.sampleA)
        let b = try await generator.generate(.sampleB)
        XCTAssertEqual(
            (b.shirt.maximum.y - b.shirt.minimum.y) / (a.shirt.maximum.y - a.shirt.minimum.y),
            170.0 / 180.0,
            accuracy: 0.003
        )
        XCTAssertEqual(
            (b.shorts.maximum.y - b.shorts.minimum.y) / (a.shorts.maximum.y - a.shorts.minimum.y),
            170.0 / 180.0,
            accuracy: 0.003
        )
        XCTAssertGreaterThan(
            regionWidth(mesh: b.shirt, height: 1.7, band: 0.69...0.75, xLimit: 0.5),
            regionWidth(mesh: a.shirt, height: 1.8, band: 0.69...0.75, xLimit: 0.5) + 0.01
        )
        XCTAssertGreaterThan(
            regionWidth(mesh: b.shorts, height: 1.7, band: 0.48...0.54, xLimit: 0.25),
            regionWidth(mesh: a.shorts, height: 1.8, band: 0.48...0.54, xLimit: 0.25) + 0.005
        )
    }

    func testEveryParameterChangesItsCorrespondingGeometryIndependently() async throws {
        let base = MeasurementAvatarInput.sampleA
        let baseline = try await MeasurementAvatarGenerator().generate(base)
        let variants: [(MeasurementAvatarInput, Int, Double)] = [
            (try MeasurementAvatarInput(heightCM: 185, chestCM: 96, waistCM: 80, hipsCM: 98, shouldersCM: 43), 0, 1.85),
            (try MeasurementAvatarInput(heightCM: 180, chestCM: 105, waistCM: 80, hipsCM: 98, shouldersCM: 43), 1, 1.05),
            (try MeasurementAvatarInput(heightCM: 180, chestCM: 96, waistCM: 90, hipsCM: 98, shouldersCM: 43), 2, 0.90),
            (try MeasurementAvatarInput(heightCM: 180, chestCM: 96, waistCM: 80, hipsCM: 110, shouldersCM: 43), 3, 1.10),
            (try MeasurementAvatarInput(heightCM: 180, chestCM: 96, waistCM: 80, hipsCM: 98, shouldersCM: 50), 4, 0.50)
        ]
        for (variant, dimension, target) in variants {
            let result = try await MeasurementAvatarGenerator().generate(variant)
            XCTAssertNotEqual(result.body.vertices.map(\.position), baseline.body.vertices.map(\.position))
            switch dimension {
            case 0: XCTAssertEqual(result.body.maximum.y - result.body.minimum.y, Float(target), accuracy: 0.003)
            case 1: XCTAssertEqual(perimeter(mesh: result.body, y: 0.72 * 1.8), Float(target), accuracy: 0.025)
            case 2: XCTAssertEqual(perimeter(mesh: result.body, y: 0.57 * 1.8), Float(target), accuracy: 0.025)
            case 3: XCTAssertEqual(perimeter(mesh: result.body, y: 0.51 * 1.8), Float(target), accuracy: 0.025)
            default: XCTAssertEqual(sectionWidth(mesh: result.body, y: 0.755 * 1.8), Float(target), accuracy: 0.025)
            }
        }
    }

    func testTopologyNormalsSymmetryAndDeterminism() async throws {
        let generator = MeasurementAvatarGenerator()
        let first = try await generator.generate(.sampleA).body
        let second = try await generator.generate(.sampleA).body
        XCTAssertEqual(first.indices, second.indices)
        XCTAssertEqual(first.vertices.map(\.position), second.vertices.map(\.position))
        XCTAssertEqual(first.indices.count % 3, 0)
        XCTAssertLessThan(first.vertices.count, Int(UInt16.max))
        XCTAssertTrue(first.indices.allSatisfy { Int($0) < first.vertices.count })
        XCTAssertEqual(first.minimum.y, 0, accuracy: 0.0001)
        XCTAssertEqual(first.maximum.y, 1.8, accuracy: 0.003)
        var edgeUses: [UInt64: Int] = [:]
        for offset in stride(from: 0, to: first.indices.count, by: 3) {
            let triangle = [Int(first.indices[offset]), Int(first.indices[offset + 1]), Int(first.indices[offset + 2])]
            for (a,b) in [(triangle[0],triangle[1]), (triangle[1],triangle[2]), (triangle[2],triangle[0])] {
                let low = UInt32(min(a,b)), high = UInt32(max(a,b))
                edgeUses[UInt64(low) << 32 | UInt64(high), default: 0] += 1
            }
        }
        XCTAssertTrue(edgeUses.values.allSatisfy { $0 == 2 })
        for vertex in first.vertices {
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.002)
        }
        // The pinned triangulation has unpaired diagonals: a mirrored surface
        // point need not be a vertex after subdivision. Check actual section
        // envelopes and paired-limb perimeters, not tessellation correspondence.
        for fraction in [Float(0.15), 0.35, 0.51, 0.57, 0.72, 0.755, 0.90] {
            let loops = sectionLoops(mesh: first, y: fraction * 1.8)
            let minimum = try XCTUnwrap(loops.map(\.minimumX).min())
            let maximum = try XCTUnwrap(loops.map(\.maximumX).max())
            XCTAssertEqual(minimum, -maximum, accuracy: 0.0025,
                           "Left/right anatomy should remain balanced at height \(fraction)")
            let left = loops.filter { $0.maximumX < 0 }.reduce(Float(0)) { $0 + $1.perimeter }
            let right = loops.filter { $0.minimumX > 0 }.reduce(Float(0)) { $0 + $1.perimeter }
            XCTAssertEqual(left, right, accuracy: 0.005, "Paired limb surfaces should have matching cross sections")
        }
    }

    func testTorsoInputsPreserveHeadDetailAndHandDepth() async throws {
        let generator = MeasurementAvatarGenerator()
        let original = try await generator.generate(.sampleA).body
        let broadInput = try MeasurementAvatarInput(heightCM: 180, chestCM: 110, waistCM: 100, hipsCM: 112, shouldersCM: 48)
        let broad = try await generator.generate(broadInput).body
        var headChange: Float = 0
        var handDepthChange: Float = 0
        var armTranslationError: Float = 0
        for (before, after) in zip(original.vertices, broad.vertices) {
            if before.position.y > 1.8 * 0.86 {
                headChange = max(headChange, simd_distance(before.position, after.position))
            }
            if abs(before.position.x) > 0.45 {
                handDepthChange = max(handDepthChange, abs(before.position.z - after.position.z))
            }
            if abs(before.position.x) > 0.45, before.position.y < 1.8 * 0.72 {
                let expected: Float = before.position.x < 0 ? -0.025 : 0.025
                armTranslationError = max(armTranslationError, abs(after.position.x - before.position.x - expected))
            }
        }
        XCTAssertLessThan(headChange, 0.00001, "Torso dimensions must not inflate the generic head or face")
        XCTAssertLessThan(handDepthChange, 0.00001, "Hip/waist values must not thicken the A-pose hands")
        XCTAssertLessThan(armTranslationError, 0.0001,
                          "The outer arms should move with shoulder breadth, not bulge with waist/chest bands")
    }

    func testInvalidValuesAreRejectedAndPinnedTemplateIsNotMutated() async throws {
        for values in [(Double.nan, 96.0, 80.0, 98.0, 43.0), (139.9, 96, 80, 98, 43), (180, 59, 80, 98, 43), (180, 96, 141, 98, 43), (180, 96, 80, 156, 43), (180, 96, 80, 98, 66)] {
            XCTAssertThrowsError(try MeasurementAvatarInput(heightCM: values.0, chestCM: values.1, waistCM: values.2, hipsCM: values.3, shouldersCM: values.4))
        }
        let original = try HumanShowcaseAssets.load().body.vertices.map(\.position)
        _ = try await MeasurementAvatarGenerator().generate(.sampleB)
        XCTAssertEqual(try HumanShowcaseAssets.load().body.vertices.map(\.position), original)
    }

    private func regionWidth(mesh: RendererMesh, height: Float, band: ClosedRange<Float>, xLimit: Float) -> Float {
        let xValues = mesh.vertices.compactMap { vertex -> Float? in
            let fraction = vertex.position.y / height
            guard band.contains(fraction), abs(vertex.position.x) < xLimit else { return nil }
            return vertex.position.x
        }
        guard let minimum = xValues.min(), let maximum = xValues.max() else { return 0 }
        return maximum - minimum
    }

    private func sectionLoops(mesh: RendererMesh, y: Float) -> [(perimeter: Float, minimumX: Float, maximumX: Float)] {
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = [mesh.vertices[Int(mesh.indices[offset])].position,
                            mesh.vertices[Int(mesh.indices[offset + 1])].position,
                            mesh.vertices[Int(mesh.indices[offset + 2])].position]
            var hits: [SIMD2<Float>] = []
            for (i,j) in [(0,1),(1,2),(2,0)] {
                let p = triangle[i], q = triangle[j]
                if (p.y < y && q.y >= y) || (q.y < y && p.y >= y) {
                    let t = (y-p.y)/(q.y-p.y)
                    hits.append(SIMD2(p.x+t*(q.x-p.x), p.z+t*(q.z-p.z)))
                }
            }
            if hits.count == 2 { segments.append((hits[0], hits[1])) }
        }
        var points: [PositionKey: SIMD2<Float>] = [:]
        var incident: [PositionKey: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            let a = PositionKey(SIMD3(segment.0.x, 0, segment.0.y))
            let b = PositionKey(SIMD3(segment.1.x, 0, segment.1.y))
            points[a] = segment.0; points[b] = segment.1
            incident[a, default: []].append(index); incident[b, default: []].append(index)
        }
        var visitedEdges = Set<Int>()
        var loops: [(perimeter: Float, minimumX: Float, maximumX: Float)] = []
        for seed in segments.indices where !visitedEdges.contains(seed) {
            var pending = [PositionKey(SIMD3(segments[seed].0.x, 0, segments[seed].0.y))]
            var visitedPoints = Set<PositionKey>()
            var length: Float = 0
            var minimumX = Float.greatestFiniteMagnitude
            var maximumX = -Float.greatestFiniteMagnitude
            while let point = pending.popLast() {
                guard visitedPoints.insert(point).inserted else { continue }
                if let position = points[point] {
                    minimumX = min(minimumX, position.x); maximumX = max(maximumX, position.x)
                }
                for edge in incident[point] ?? [] where visitedEdges.insert(edge).inserted {
                    length += simd_distance(segments[edge].0, segments[edge].1)
                    for endpoint in [segments[edge].0, segments[edge].1] {
                        pending.append(PositionKey(SIMD3(endpoint.x, 0, endpoint.y)))
                    }
                }
            }
            loops.append((length, minimumX, maximumX))
        }
        return loops
    }

    private func centralLoop(mesh: RendererMesh, y: Float) -> (perimeter: Float, minimumX: Float, maximumX: Float) {
        sectionLoops(mesh: mesh, y: y)
            .filter { abs(($0.minimumX + $0.maximumX) * 0.5) < 0.12 }
            .max { $0.perimeter < $1.perimeter }!
    }

    private func sectionWidth(mesh: RendererMesh, y: Float) -> Float {
        let loop = centralLoop(mesh: mesh, y: y)
        return loop.maximumX - loop.minimumX
    }

    private func perimeter(mesh: RendererMesh, y: Float) -> Float {
        centralLoop(mesh: mesh, y: y).perimeter
    }
}
#endif
