#if DEBUG
import simd
import XCTest
@testable import FitCheck

final class RendererMeshTests: XCTestCase {
    func testMeshesContainFiniteIndexedNondegenerateOutwardGeometry() {
        for mesh in [RendererProceduralAssets.mannequin(), RendererProceduralAssets.garment()] {
            XCTAssertFalse(mesh.vertices.isEmpty)
            XCTAssertFalse(mesh.indices.isEmpty)
            XCTAssertEqual(mesh.indices.count % 3, 0)
            for vertex in mesh.vertices {
                XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
                XCTAssertTrue(vertex.normal.x.isFinite && vertex.normal.y.isFinite && vertex.normal.z.isFinite)
                XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
            }
            for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
                let ia = Int(mesh.indices[offset]), ib = Int(mesh.indices[offset + 1]), ic = Int(mesh.indices[offset + 2])
                XCTAssertLessThan(ia, mesh.vertices.count)
                XCTAssertLessThan(ib, mesh.vertices.count)
                XCTAssertLessThan(ic, mesh.vertices.count)
                let a = mesh.vertices[ia], b = mesh.vertices[ib], c = mesh.vertices[ic]
                let cross = simd_cross(b.position - a.position, c.position - a.position)
                XCTAssertGreaterThan(simd_length(cross), 1e-8, "degenerate triangle at index \(offset)")
                XCTAssertGreaterThan(simd_dot(cross, a.normal + b.normal + c.normal), 0, "inward winding at index \(offset)")
            }
            let actualMin = SIMD3(mesh.vertices.map { $0.position.x }.min()!, mesh.vertices.map { $0.position.y }.min()!, mesh.vertices.map { $0.position.z }.min()!)
            let actualMax = SIMD3(mesh.vertices.map { $0.position.x }.max()!, mesh.vertices.map { $0.position.y }.max()!, mesh.vertices.map { $0.position.z }.max()!)
            XCTAssertEqual(mesh.minimum, actualMin)
            XCTAssertEqual(mesh.maximum, actualMax)
        }
    }

    func testMannequinUsesMetreScaleFloorOriginAndForwardFacingFeet() {
        let mesh = RendererProceduralAssets.mannequin()
        XCTAssertGreaterThan(mesh.maximum.y - mesh.minimum.y, 1.7)
        XCTAssertLessThan(mesh.maximum.y - mesh.minimum.y, 1.8)
        XCTAssertGreaterThan(mesh.maximum.x - mesh.minimum.x, 0.5)
        XCTAssertLessThan(mesh.maximum.x - mesh.minimum.x, 0.8)
        XCTAssertGreaterThan(mesh.maximum.z - mesh.minimum.z, 0.25)
        XCTAssertLessThan(mesh.maximum.z - mesh.minimum.z, 0.5)
        XCTAssertEqual(mesh.minimum.y, 0, accuracy: 0.001)

        // The lowest two broad components are feet: their front (+Z) extent exceeds their rear extent.
        let footVertices = mesh.vertices.filter { $0.position.y < 0.10 && abs($0.position.x) > 0.02 }
        XCTAssertGreaterThan(footVertices.count, 0)
        let front = footVertices.map { $0.position.z }.max()!
        let rear = footVertices.map { $0.position.z }.min()!
        XCTAssertGreaterThan(front, abs(rear))
        XCTAssertNotEqual(front, rear)
    }

    func testGarmentIsSeparateOpenThreeDimensionalShellWithActualRings() {
        let garment = RendererProceduralAssets.garment()
        XCTAssertGreaterThan(garment.maximum.y - garment.minimum.y, 0.4)
        XCTAssertGreaterThan(garment.maximum.x - garment.minimum.x, 0.4)
        XCTAssertGreaterThan(garment.maximum.z - garment.minimum.z, 0.15)

        // Uncapped openings have boundary edges forming closed loops, not centre-filled disks.
        var edgeCounts: [UInt32: Int] = [:]
        for offset in stride(from: 0, to: garment.indices.count, by: 3) {
            let triangle = [garment.indices[offset], garment.indices[offset + 1], garment.indices[offset + 2]]
            for edge in 0..<3 {
                let a = triangle[edge], b = triangle[(edge + 1) % 3]
                let key = UInt32(min(a, b)) << 16 | UInt32(max(a, b))
                edgeCounts[key, default: 0] += 1
            }
        }
        let boundaries = edgeCounts.filter { $0.value == 1 }.keys
        for height in [garment.minimum.y, garment.maximum.y] {
            let ring = garment.vertices.indices.filter { abs(garment.vertices[$0].position.y - height) < 0.0001 }
            XCTAssertFalse(ring.isEmpty)
            for index in ring {
                let adjacent = boundaries.filter { Int($0 >> 16) == index || Int($0 & 0xffff) == index }
                XCTAssertEqual(adjacent.count, 2, "Open rim vertices must have two boundary neighbors")
            }
            XCTAssertTrue(ring.contains { garment.vertices[$0].position.z > 0.05 })
            XCTAssertTrue(ring.contains { garment.vertices[$0].position.z < -0.05 })
        }
    }
}
#endif
