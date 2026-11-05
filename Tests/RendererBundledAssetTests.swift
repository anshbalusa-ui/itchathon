#if DEBUG
import Foundation
import simd
import XCTest
@testable import FitCheck

final class RendererBundledAssetTests: XCTestCase {
    func testReviewedFileLoadsActualBoundsNormalsAndWinding() async throws {
        let loaded = try await RendererBundledAssetLoader().load(.reviewedVest)
        XCTAssertEqual(loaded.descriptor, .reviewedVest)
        XCTAssertEqual(loaded.mesh.vertices.count, 108)
        XCTAssertEqual(loaded.mesh.indices.count, 108)
        XCTAssertEqual(loaded.mesh.minimum, SIMD3(-0.29, 0.84, -0.16))
        XCTAssertEqual(loaded.mesh.maximum, SIMD3(0.29, 1.43, 0.215))
        for vertex in loaded.mesh.vertices {
            XCTAssertEqual(simd_length(vertex.normal), 1, accuracy: 0.001)
        }
        for index in stride(from: 0, to: loaded.mesh.indices.count, by: 3) {
            let a = loaded.mesh.vertices[Int(loaded.mesh.indices[index])]
            let b = loaded.mesh.vertices[Int(loaded.mesh.indices[index + 1])]
            let c = loaded.mesh.vertices[Int(loaded.mesh.indices[index + 2])]
            let cross = simd_cross(b.position - a.position, c.position - a.position)
            XCTAssertGreaterThan(simd_length_squared(cross), 1e-10)
            for normal in [a.normal, b.normal, c.normal] {
                XCTAssertGreaterThan(simd_dot(simd_normalize(cross), normal), 0.9)
            }
        }
    }

    func testBundledDescriptorCannotMasqueradeAsProceduralCatalogFixture() throws {
        let bundled = RendererBundledAssetDescriptor.reviewedVest
        XCTAssertThrowsError(try bundled.asset.validate(for: .garment)) { error in
            XCTAssertEqual(error as? RendererFailure, .unsupportedAsset)
        }
        let products = try CatalogDocument.decode(SyntheticCatalog.data).products
        for product in products where product.category == .tshirt && product.id.productID != "archived-tee" {
            let variant = try XCTUnwrap(product.variants.first { $0.availability == .available })
            let association = CatalogPreviewAssociation(fixture: bundled.asset)
            XCTAssertEqual(association.resolve(
                product: product, selectedVariant: variant,
                selectedColorID: variant.colorID, selectedSizeID: variant.sizeID
            ), .unavailable(.incompatibleFixture))
        }
    }

    func testMetadataPolicyRejectsAlteredIdentityRightsUnitsAndLayout() throws {
        let changes: [(String, Any)] = [
            ("format", "obj"), ("schemaVersion", 99), ("assetID", "unrelated-asset"),
            ("revision", 2), ("type", "proceduralFixture"), ("role", "mannequin"),
            ("coordinateSystem", "left-handed"), ("unit", "centimetre"), ("origin", "waist"),
            ("scale", 0.01), ("source", "remote"), ("provenance", "retailer"),
            ("license", "commercial"), ("isLocallyOwned", false), ("personalized", true),
            ("productID", "everyday-tee"), ("variantID", "everyday-navy-small"),
            ("rendererCapability", "unknown-renderer"), ("materialModel", "unlit"),
            ("submeshCount", 2), ("topology", "lines")
        ]
        for (key, value) in changes {
            let data = try changedPackage { $0[key] = value }
            XCTAssertThrowsError(try decode(data).validatedMesh(), "Policy field: \(key)")
        }
    }

    func testUnknownTopLevelAndVertexFieldsAreRejectedDuringDecode() throws {
        let unknownTopLevel = try changedPackage { $0["textures"] = ["unreviewed.png"] }
        XCTAssertThrowsError(try decode(unknownTopLevel))
        let unknownVertex = try changedVertices { $0[0]["textureURL"] = "unreviewed.png" }
        XCTAssertThrowsError(try decode(unknownVertex))
        let omittedNullAssociation = try changedPackage { $0.removeValue(forKey: "productID") }
        XCTAssertThrowsError(try decode(omittedNullAssociation))
    }

    func testMalformedTruncatedAndWrongNumericTypesAreRejected() throws {
        let valid = try reviewedData()
        for data in [Data(), Data(valid.prefix(valid.count / 2)), Data("[]".utf8)] {
            XCTAssertThrowsError(try decode(data))
        }
        let nonnumeric = try changedVertices { $0[0]["px"] = "not-a-coordinate" }
        XCTAssertThrowsError(try decode(nonnumeric))
        let fractionalIndex = try changedPackage { $0["indices"] = [0, 1.5, 2] }
        XCTAssertThrowsError(try decode(fractionalIndex))
    }

    func testNonfiniteExtremeAndInvalidNormalsCannotBecomeMesh() throws {
        // The production decoder rejects these strings. This explicit test-only strategy
        // reaches the finite-value validator independently of JSON's numeric restrictions.
        let ieeeDecoder = JSONDecoder()
        ieeeDecoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        for key in ["px", "py", "pz", "nx", "ny", "nz"] {
            for value in ["NaN", "Infinity", "-Infinity"] {
                let data = try changedVertices { $0[0][key] = value }
                XCTAssertThrowsError(try decode(data, decoder: ieeeDecoder).validatedMesh())
            }
        }
        for (key, value): (String, Double) in [("px", 99), ("py", -1), ("pz", 99), ("nx", 0), ("ny", 10)] {
            let data = try changedVertices { vertices in
                if key == "nx" {
                    vertices[0]["nx"] = 0
                    vertices[0]["ny"] = 0
                    vertices[0]["nz"] = 0
                } else {
                    vertices[0][key] = value
                }
            }
            XCTAssertThrowsError(try decode(data).validatedMesh())
        }
    }

    func testIndicesRejectNegativeOverflowOutOfRangeAndNonTriangleCounts() throws {
        for indices: [Any] in [[0, 1, -1], [0, 1, UInt64.max], [0, 1, 108], [0, 1, 65_536], [0, 1]] {
            let data = try changedPackage { $0["indices"] = indices }
            XCTAssertThrowsError(try decode(data).validatedMesh())
        }
    }

    func testDegenerateAndReversedTrianglesAreNotRepaired() throws {
        let duplicateIndex = try changedPackage { object in
            var indices = try XCTUnwrap(object["indices"] as? [Int])
            indices[1] = indices[0]
            object["indices"] = indices
        }
        XCTAssertThrowsError(try decode(duplicateIndex).validatedMesh())
        let reversed = try changedPackage { object in
            var indices = try XCTUnwrap(object["indices"] as? [Int])
            indices.swapAt(0, 1)
            object["indices"] = indices
        }
        XCTAssertThrowsError(try decode(reversed).validatedMesh())
        let coincident = try changedVertices { vertices in
            for key in ["px", "py", "pz"] { vertices[1][key] = vertices[0][key] }
        }
        XCTAssertThrowsError(try decode(coincident).validatedMesh())
    }

    func testEmptyAndExcessiveArraysFailWithoutLargeAllocation() throws {
        let changes: [(String, Any)] = [
            ("vertices", []), ("indices", []), ("indices", Array(repeating: 0, count: 6_147))
        ]
        for (key, value) in changes {
            let data = try changedPackage { $0[key] = value }
            XCTAssertThrowsError(try decode(data).validatedMesh())
        }
        let manyVertices = try changedVertices { vertices in
            vertices = Array(repeating: vertices[0], count: 1_025)
        }
        XCTAssertThrowsError(try decode(manyVertices).validatedMesh())
    }

    func testChangedFixtureBoundsAreRejectedEvenWithOtherwiseValidFaces() throws {
        let shifted = try changedVertices { vertices in
            for index in vertices.indices {
                vertices[index]["py"] = try XCTUnwrap(vertices[index]["py"] as? Double) + 0.01
            }
        }
        XCTAssertThrowsError(try decode(shifted).validatedMesh())
    }

    func testCheckedBufferSizingRejectsOverflowWithoutAllocatingArrays() throws {
        let sizes = try RendererMeshPackage.validatedBufferSizes(vertexCount: 108, indexCount: 108)
        XCTAssertEqual(sizes.vertices, 3_456)
        XCTAssertEqual(sizes.indices, 216)
        XCTAssertThrowsError(try RendererMeshPackage.validatedBufferSizes(vertexCount: .max, indexCount: 3))
        let largeTriangleCount = Int.max - Int.max % 3
        XCTAssertThrowsError(try RendererMeshPackage.validatedBufferSizes(vertexCount: 3, indexCount: largeTriangleCount))
        XCTAssertThrowsError(try RendererMeshPackage.validatedBufferSizes(vertexCount: -1, indexCount: 3))
    }

    private func reviewedData() throws -> Data {
        let root = try XCTUnwrap(Bundle.main.resourceURL)
        return try Data(contentsOf: root.appendingPathComponent("FitCheckDevelopmentAssets/FitCheckGeometricVest.fitmesh"))
    }

    private func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> RendererMeshPackage {
        try decoder.decode(RendererMeshPackage.self, from: data)
    }

    private func changedPackage(_ mutation: (inout [String: Any]) throws -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: reviewedData()) as? [String: Any])
        try mutation(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func changedVertices(_ mutation: (inout [[String: Any]]) throws -> Void) throws -> Data {
        try changedPackage { object in
            var vertices = try XCTUnwrap(object["vertices"] as? [[String: Any]])
            try mutation(&vertices)
            object["vertices"] = vertices
        }
    }
}
#endif
