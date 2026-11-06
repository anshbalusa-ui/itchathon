import CryptoKit
import Foundation
import simd

struct HumanShowcaseMeshes: Sendable {
    let body: RendererMesh
    let shirt: RendererMesh
    let vest: RendererMesh
    let shorts: RendererMesh

    // Only this file's pinned-payload admission may mint a human showcase.
    fileprivate init(body: RendererMesh, shirt: RendererMesh, vest: RendererMesh, shorts: RendererMesh) {
        self.body = body
        self.shirt = shirt
        self.vest = vest
        self.shorts = shorts
    }
}

enum HumanShowcaseAssetFailure: Error, Equatable {
    case missingResource
    case rejectedPayload
}

enum HumanShowcaseAssets {
    private static let resourceName = "human-showcase-v1"
    private static let resourceExtension = "bin"
    private static let sha256: [UInt8] = [
        0x69,0x77,0xbd,0x1a,0xeb,0xa5,0x4c,0x9f,0x4e,0xf8,0x2f,0x9d,0x7f,0x9b,0x8b,0x99,
        0x6d,0x03,0x0b,0x27,0x58,0xe2,0x26,0xb6,0x1d,0xcb,0x9f,0xbc,0xcf,0xe4,0xf6,0xe9
    ]
    private static let maximumPayloadBytes = 2_000_000
    private static let maximumVertices = 20_000
    private static let maximumIndices = 100_000

    static func load(bundle: Bundle = .main) throws -> HumanShowcaseMeshes {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "HumanShowcase"),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw HumanShowcaseAssetFailure.missingResource
        }
        return try decode(data)
    }

    // Internal for focused malformed-payload tests; callers load only the pinned bundled resource.
    static func decode(_ data: Data) throws -> HumanShowcaseMeshes {
        guard data.count <= maximumPayloadBytes,
              SHA256.hash(data: data).elementsEqual(sha256) else { throw HumanShowcaseAssetFailure.rejectedPayload }
        var reader = HumanShowcaseReader(data: data)
        guard try reader.hasMagic(), try reader.u32() == 1 else {
            throw HumanShowcaseAssetFailure.rejectedPayload
        }
        var meshes: [RendererMesh] = []
        meshes.reserveCapacity(4)
        for expectedKind in 0..<4 {
            let kind = try reader.u8()
            let vertexCount = Int(try reader.u32())
            let indexCount = Int(try reader.u32())
            let clearanceCount = Int(try reader.u32())
            guard Int(kind) == expectedKind,
                  vertexCount >= 3, vertexCount <= maximumVertices,
                  indexCount >= 3, indexCount <= maximumIndices, indexCount % 3 == 0,
                  (expectedKind == 0 ? clearanceCount == 0 : clearanceCount == vertexCount),
                  reader.remaining >= vertexCount * 24 + indexCount * 2 + clearanceCount * 4 else {
                throw HumanShowcaseAssetFailure.rejectedPayload
            }
            var vertices: [RendererVertex] = []
            vertices.reserveCapacity(vertexCount)
            for _ in 0..<vertexCount {
                let position = SIMD3(try reader.f32(), try reader.f32(), try reader.f32())
                let normal = SIMD3(try reader.f32(), try reader.f32(), try reader.f32())
                guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
                      normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
                      abs(position.x) <= 0.8, position.y >= -0.02, position.y <= 1.85,
                      abs(position.z) <= 0.8,
                      abs(simd_length(normal) - 1) <= 0.02 else {
                    throw HumanShowcaseAssetFailure.rejectedPayload
                }
                vertices.append(RendererVertex(position: position, normal: normal))
            }
            var indices: [UInt16] = []
            indices.reserveCapacity(indexCount)
            for _ in 0..<indexCount {
                let index = try reader.u16()
                guard Int(index) < vertexCount else { throw HumanShowcaseAssetFailure.rejectedPayload }
                indices.append(index)
            }
            var clearance: [Float]? = nil
            if clearanceCount > 0 {
                var values: [Float] = []
                values.reserveCapacity(clearanceCount)
                for _ in 0..<clearanceCount {
                    let gap = try reader.f32()
                    guard gap.isFinite, (0.002...0.1).contains(gap) else {
                        throw HumanShowcaseAssetFailure.rejectedPayload
                    }
                    values.append(gap)
                }
                clearance = values
            }
            let bounds = vertices.reduce(into: (min: SIMD3<Float>(repeating: .greatestFiniteMagnitude), max: SIMD3<Float>(repeating: -.greatestFiniteMagnitude))) { result, vertex in
                result.min = simd.min(result.min, vertex.position)
                result.max = simd.max(result.max, vertex.position)
            }
            meshes.append(RendererMesh(vertices: vertices, indices: indices,
                                       minimum: bounds.min, maximum: bounds.max,
                                       sampleClearance: clearance))
        }
        guard reader.remaining == 0, meshes.count == 4,
              meshes[0].vertices.count > 10_000,
              meshes[0].minimum.y >= -0.001, meshes[0].maximum.y >= 1.79,
              meshes[0].maximum.y <= 1.81,
              meshes[1].sampleClearance?.count == meshes[1].vertices.count,
              meshes[2].sampleClearance?.count == meshes[2].vertices.count,
              meshes[3].sampleClearance?.count == meshes[3].vertices.count else {
            throw HumanShowcaseAssetFailure.rejectedPayload
        }
        return HumanShowcaseMeshes(body: meshes[0], shirt: meshes[1], vest: meshes[2], shorts: meshes[3])
    }
}

private struct HumanShowcaseReader {
    let data: Data
    private(set) var offset = 0
    var remaining: Int { data.count - offset }

    mutating func hasMagic() throws -> Bool {
        guard remaining >= 8 else { throw HumanShowcaseAssetFailure.rejectedPayload }
        let matches = data.withUnsafeBytes { raw in
            raw.bindMemory(to: UInt8.self).prefix(8).elementsEqual("FCHUMAN1".utf8)
        }
        offset += 8
        return matches
    }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw HumanShowcaseAssetFailure.rejectedPayload }
        let value = data.withUnsafeBytes { raw in raw.load(fromByteOffset: offset, as: UInt8.self) }
        offset += 1
        return value
    }
    mutating func u16() throws -> UInt16 {
        guard remaining >= 2 else { throw HumanShowcaseAssetFailure.rejectedPayload }
        let value = data.withUnsafeBytes { raw in raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
        offset += 2
        return UInt16(littleEndian: value)
    }
    mutating func u32() throws -> UInt32 {
        guard remaining >= 4 else { throw HumanShowcaseAssetFailure.rejectedPayload }
        let value = data.withUnsafeBytes { raw in raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        offset += 4
        return UInt32(littleEndian: value)
    }
    mutating func f32() throws -> Float { Float(bitPattern: try u32()) }
}
