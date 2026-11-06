#if DEBUG
import Foundation
import simd
import XCTest
@testable import FitCheck

final class HumanShowcaseAssetTests: XCTestCase {
    func testPinnedAssetLoadsWithAnatomicalScaleTopologyAndAuthoredSpacing() throws {
        let meshes = try HumanShowcaseAssets.load()
        let body = meshes.body
        XCTAssertGreaterThan(body.vertices.count, 10_000)
        XCTAssertEqual(body.vertices.count, Set(body.indices).count)
        XCTAssertLessThanOrEqual(body.vertices.count, Int(UInt16.max))
        XCTAssertEqual(body.indices.count % 3, 0)
        XCTAssertEqual(body.minimum.y, 0, accuracy: 0.002)
        XCTAssertEqual(body.maximum.y, 1.8, accuracy: 0.002)
        XCTAssertGreaterThan(body.maximum.x - body.minimum.x, 0.9, "A-pose arms should span the body width")
        XCTAssertGreaterThan(body.maximum.z - body.minimum.z, 0.35, "The torso, face and feet should retain front-to-back volume")
        XCTAssertGreaterThan(body.vertices.filter { $0.position.y > 1.65 }.count, 100, "The detailed head surface is present")
        XCTAssertGreaterThan(body.vertices.filter { $0.position.x > 0.35 && $0.position.y > 0.8 }.count, 100, "The right arm/hand surface is present")
        XCTAssertGreaterThan(body.vertices.filter { $0.position.x < -0.35 && $0.position.y > 0.8 }.count, 100, "The left arm/hand surface is present")
        XCTAssertTrue(body.vertices.contains { $0.position.x < -0.08 && $0.position.y < 0.12 }, "The left foot reaches the floor")
        XCTAssertTrue(body.vertices.contains { $0.position.x > 0.08 && $0.position.y < 0.12 }, "The right foot reaches the floor")

        for mesh in [body, meshes.shirt, meshes.vest, meshes.shorts] {
            XCTAssertEqual(mesh.indices.count % 3, 0)
            XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count })
            for vertex in mesh.vertices {
                XCTAssertTrue(vertex.position.x.isFinite && vertex.position.y.isFinite && vertex.position.z.isFinite)
                XCTAssertTrue(vertex.normal.x.isFinite && vertex.normal.y.isFinite && vertex.normal.z.isFinite)
                XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.02)
            }
        }

        // The source body is bilaterally symmetric. Quantized positions make this
        // robust to float conversion while checking actual paired anatomy.
        let positionKeys = Set(body.vertices.map { key($0.position) })
        for vertex in body.vertices {
            let p = vertex.position
            XCTAssertTrue(positionKeys.contains(key(SIMD3(-p.x, p.y, p.z))), "Unpaired body surface at \(p)")
        }
        assertClosedTwoManifold(body)

        for garment in [meshes.shirt, meshes.vest, meshes.shorts] {
            let gaps = try XCTUnwrap(garment.sampleClearance)
            XCTAssertEqual(gaps.count, garment.vertices.count)
            XCTAssertGreaterThan(Set(gaps.map { Int(($0 * 1_000).rounded()) }).count, 1, "Sample spacing must vary by garment region")
            XCTAssertTrue(gaps.allSatisfy { $0.isFinite && (0.002...0.1).contains($0) })
            assertOpenManifoldShell(garment)
            XCTAssertTrue(garment.vertices.allSatisfy { $0.position.y > 0.45 && $0.position.y < 1.7 })
        }
        for garment in [meshes.shirt, meshes.vest] {
            let gaps = try XCTUnwrap(garment.sampleClearance)
            XCTAssertTrue(gaps.contains { $0 <= 0.006 }, "The illustration needs genuinely close-spaced shell vertices")
            XCTAssertTrue(gaps.contains { $0 >= 0.028 }, "The illustration needs genuinely roomier shell vertices")
        }
    }

    func testAdmissionRejectsModifiedTruncatedAndOversizedPayloads() throws {
        let bundle = Bundle.main
        let url = try XCTUnwrap(bundle.url(forResource: "human-showcase-v1", withExtension: "bin", subdirectory: "HumanShowcase"))
        let good = try Data(contentsOf: url)
        XCTAssertThrowsError(try HumanShowcaseAssets.decode(Data(good.dropLast())))
        var mutated = good
        mutated[mutated.startIndex + 16] ^= 0x01
        XCTAssertThrowsError(try HumanShowcaseAssets.decode(mutated))
        XCTAssertThrowsError(try HumanShowcaseAssets.decode(Data(repeating: 0, count: 2_000_001)))
    }

    private func key(_ p: SIMD3<Float>) -> String {
        "\(Int((p.x * 1_000).rounded())):\(Int((p.y * 1_000).rounded())):\(Int((p.z * 1_000).rounded()))"
    }

    private func assertClosedTwoManifold(_ mesh: RendererMesh, file: StaticString = #filePath, line: UInt = #line) {
        var edges: [UInt32: Int] = [:]
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = [mesh.indices[i], mesh.indices[i + 1], mesh.indices[i + 2]]
            for edge in [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])] {
                let a = UInt32(min(edge.0, edge.1)); let b = UInt32(max(edge.0, edge.1))
                edges[(a << 16) | b, default: 0] += 1
            }
        }
        XCTAssertFalse(edges.isEmpty, file: file, line: line)
        XCTAssertTrue(edges.values.allSatisfy { $0 == 2 }, "Body surface must be continuous and manifold", file: file, line: line)
    }

    private func assertOpenManifoldShell(_ mesh: RendererMesh, file: StaticString = #filePath, line: UInt = #line) {
        var edges: [UInt32: Int] = [:]
        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let triangle = [mesh.indices[i], mesh.indices[i + 1], mesh.indices[i + 2]]
            for edge in [(triangle[0], triangle[1]), (triangle[1], triangle[2]), (triangle[2], triangle[0])] {
                let a = UInt32(min(edge.0, edge.1)); let b = UInt32(max(edge.0, edge.1))
                edges[(a << 16) | b, default: 0] += 1
            }
        }
        XCTAssertTrue(edges.values.contains(1), "Garment hem/opening boundaries should remain open", file: file, line: line)
        XCTAssertTrue(edges.values.allSatisfy { $0 <= 2 }, "Garment surface must not contain nonmanifold edges", file: file, line: line)
    }
}
#endif
