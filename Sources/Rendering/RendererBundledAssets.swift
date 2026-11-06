#if DEBUG
import CryptoKit
import Darwin
import Foundation
import simd

struct RendererBundledAssetDescriptor: Hashable, Sendable {
    let asset: RendererAssetDescriptor
    let resourceName: String
    let resourceExtension: String
    let sha256: [UInt8]

    static let reviewedVest = RendererBundledAssetDescriptor(
        asset: RendererAssetDescriptor(
            type: .bundledMeshPackage, role: .garment, schemaVersion: 1,
            assetID: "fitcheck.bundled-geometric-vest", revision: 1,
            coordinateSystem: RendererCoordinates.convention, unit: RendererCoordinates.worldUnit,
            origin: RendererCoordinates.meshOrigin, scale: 1, source: .bundledFixture,
            provenance: .firstPartyFixture, license: .internalDevelopmentOnly,
            isLocallyOwned: true, productID: nil, variantID: nil,
            materialModel: .solidColorLambert, rendererCapability: "fitcheck.r0.metal.v1", personalized: false
        ),
        resourceName: "FitCheckGeometricVest", resourceExtension: "fitmesh",
        sha256: [0xec, 0xc2, 0xdf, 0x7e, 0x57, 0xf5, 0xa1, 0x2a, 0xc8, 0x9f, 0x4b, 0xd1, 0x6b, 0xb5, 0x1d, 0x10, 0x17, 0x18, 0x78, 0x0e, 0xe6, 0x09, 0xa7, 0x2f, 0x41, 0xc8, 0xff, 0x1b, 0x65, 0x3f, 0x7f, 0x30]
    )
    static var incompatibleDemo: Self {
        var hash = reviewedVest.sha256
        hash[0] ^= 1
        return Self(asset: reviewedVest.asset, resourceName: reviewedVest.resourceName, resourceExtension: reviewedVest.resourceExtension, sha256: hash)
    }

    func validate() throws {
        guard self == Self.reviewedVest else { throw RendererAssetLoadFailure.unsupportedAsset }
    }
}

enum RendererAssetLoadFailure: Error, Equatable, Sendable, LocalizedError {
    case unsupportedAsset, missingResource, unreadableResource, sizeLimit, integrityMismatch, malformedPackage, invalidGeometry
    case graphicsUnavailable
    var errorDescription: String? {
        switch self {
        case .unsupportedAsset: "This bundled asset is not supported."
        case .missingResource: "The bundled asset is unavailable."
        case .unreadableResource: "The bundled asset cannot be read."
        case .sizeLimit: "The bundled asset exceeds the permitted size."
        case .integrityMismatch: "The bundled asset failed integrity verification."
        case .malformedPackage: "The bundled asset package is malformed."
        case .invalidGeometry: "The bundled asset geometry is invalid."
        case .graphicsUnavailable: "The device could not prepare this garment for rendering. You can retry."
        }
    }
}

struct RendererLoadedGarment: Sendable {
    let descriptor: RendererBundledAssetDescriptor
    let mesh: RendererMesh
    fileprivate init(descriptor: RendererBundledAssetDescriptor, mesh: RendererMesh) { self.descriptor = descriptor; self.mesh = mesh }
}

protocol RendererGarmentLoading: Sendable {
    func load(_ descriptor: RendererBundledAssetDescriptor) async throws -> RendererLoadedGarment
}

actor RendererBundledAssetLoader: RendererGarmentLoading {
    static let maximumBytes = 65_536
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func load(_ descriptor: RendererBundledAssetDescriptor) async throws -> RendererLoadedGarment {
        try Task.checkCancellation()
        try descriptor.validate()
        let data = try readReviewedResource(descriptor)
        try Task.checkCancellation()
        guard SHA256.hash(data: data).elementsEqual(descriptor.sha256) else {
            throw RendererAssetLoadFailure.integrityMismatch
        }
        let package: RendererMeshPackage
        do {
            package = try JSONDecoder().decode(RendererMeshPackage.self, from: data)
        } catch {
            throw RendererAssetLoadFailure.malformedPackage
        }
        try Task.checkCancellation()
        let mesh = try package.validatedMesh()
        try Task.checkCancellation()
        return RendererLoadedGarment(descriptor: descriptor, mesh: mesh)
    }

    private func readReviewedResource(_ descriptor: RendererBundledAssetDescriptor) throws -> Data {
        guard let resources = bundle.resourceURL else { throw RendererAssetLoadFailure.missingResource }
        // Only this registered child directory and leaf are opened; neither may be a symlink.
        let root = resources.resolvingSymlinksInPath().appendingPathComponent("FitCheckDevelopmentAssets")
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard directory >= 0 else {
            throw errno == ENOENT ? RendererAssetLoadFailure.missingResource : .unreadableResource
        }
        defer { close(directory) }
        let name = descriptor.resourceName + "." + descriptor.resourceExtension
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard file >= 0 else {
            throw errno == ENOENT ? RendererAssetLoadFailure.missingResource : .unreadableResource
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw RendererAssetLoadFailure.unreadableResource
        }
        guard info.st_size >= 0, info.st_size <= off_t(Self.maximumBytes) else {
            throw RendererAssetLoadFailure.sizeLimit
        }
        var data = Data()
        data.reserveCapacity(Int(info.st_size) + 1)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= Self.maximumBytes {
            try Task.checkCancellation()
            let amount = min(buffer.count, Self.maximumBytes + 1 - data.count)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress!, amount) }
            if count < 0 {
                if errno == EINTR { continue }
                throw RendererAssetLoadFailure.unreadableResource
            }
            if count == 0 { break }
            data.append(contentsOf: buffer[..<count])
        }
        guard data.count <= Self.maximumBytes else { throw RendererAssetLoadFailure.sizeLimit }
        return data
    }
}

struct RendererMeshPackage: Decodable {
    let format: String, assetID: String, type: String, role: String
    let coordinateSystem: String, unit: String, origin: String
    let source: String, provenance: String, license: String
    let rendererCapability: String, materialModel: String, topology: String
    let schemaVersion: Int, revision: Int, scale: Float
    let isLocallyOwned: Bool, personalized: Bool
    let productID: String?, variantID: String?, submeshCount: Int
    let vertices: [Vertex]
    let indices: [UInt32]

    struct Vertex: Decodable {
        let px, py, pz, nx, ny, nz: Float
        private enum Keys: String, CodingKey, CaseIterable { case px, py, pz, nx, ny, nz }
        private static let fieldCount = Keys.allCases.count

        init(from decoder: Decoder) throws {
            try requireMeshFields(decoder, type: Keys.self, count: Self.fieldCount)
            let values = try decoder.container(keyedBy: Keys.self)
            px = try values.decode(Float.self, forKey: .px)
            py = try values.decode(Float.self, forKey: .py)
            pz = try values.decode(Float.self, forKey: .pz)
            nx = try values.decode(Float.self, forKey: .nx)
            ny = try values.decode(Float.self, forKey: .ny)
            nz = try values.decode(Float.self, forKey: .nz)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, schemaVersion, assetID, revision, type, role, coordinateSystem, unit, origin, scale
        case source, provenance, license, isLocallyOwned, personalized, productID, variantID
        case rendererCapability, materialModel, submeshCount, topology, vertices, indices
    }
    private static let fieldCount = CodingKeys.allCases.count

    init(from decoder: Decoder) throws {
        try requireMeshFields(decoder, type: CodingKeys.self, count: Self.fieldCount)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        assetID = try values.decode(String.self, forKey: .assetID)
        revision = try values.decode(Int.self, forKey: .revision)
        type = try values.decode(String.self, forKey: .type)
        role = try values.decode(String.self, forKey: .role)
        coordinateSystem = try values.decode(String.self, forKey: .coordinateSystem)
        unit = try values.decode(String.self, forKey: .unit)
        origin = try values.decode(String.self, forKey: .origin)
        scale = try values.decode(Float.self, forKey: .scale)
        source = try values.decode(String.self, forKey: .source)
        provenance = try values.decode(String.self, forKey: .provenance)
        license = try values.decode(String.self, forKey: .license)
        isLocallyOwned = try values.decode(Bool.self, forKey: .isLocallyOwned)
        personalized = try values.decode(Bool.self, forKey: .personalized)
        productID = try values.decodeIfPresent(String.self, forKey: .productID)
        variantID = try values.decodeIfPresent(String.self, forKey: .variantID)
        rendererCapability = try values.decode(String.self, forKey: .rendererCapability)
        materialModel = try values.decode(String.self, forKey: .materialModel)
        submeshCount = try values.decode(Int.self, forKey: .submeshCount)
        topology = try values.decode(String.self, forKey: .topology)
        vertices = try values.decode([Vertex].self, forKey: .vertices)
        indices = try values.decode([UInt32].self, forKey: .indices)
    }

    static func validatedBufferSizes(vertexCount: Int, indexCount: Int) throws -> (vertices: Int, indices: Int) {
        guard vertexCount > 0, indexCount > 0, indexCount % 3 == 0 else {
            throw RendererAssetLoadFailure.invalidGeometry
        }
        let vertexBytes = vertexCount.multipliedReportingOverflow(by: MemoryLayout<RendererVertex>.stride)
        let indexBytes = indexCount.multipliedReportingOverflow(by: MemoryLayout<UInt16>.stride)
        let total = vertexBytes.partialValue.addingReportingOverflow(indexBytes.partialValue)
        guard !vertexBytes.overflow, !indexBytes.overflow, !total.overflow,
              vertexCount <= 1024, indexCount <= 6144, total.partialValue <= 45_056 else {
            throw RendererAssetLoadFailure.sizeLimit
        }
        return (vertexBytes.partialValue, indexBytes.partialValue)
    }

    func validatedMesh() throws -> RendererMesh {
        let expected = RendererBundledAssetDescriptor.reviewedVest.asset
        guard format == "fitcheck.mesh-json", schemaVersion == expected.schemaVersion,
              assetID == expected.assetID, revision == expected.revision, type == expected.type.rawValue,
              role == expected.role.rawValue, coordinateSystem == expected.coordinateSystem,
              unit == expected.unit, origin == expected.origin, scale == expected.scale,
              source == expected.source.rawValue, provenance == expected.provenance.rawValue,
              license == expected.license.rawValue, isLocallyOwned, !personalized,
              productID == nil, variantID == nil, rendererCapability == expected.rendererCapability,
              materialModel == expected.materialModel.rawValue, submeshCount == 1, topology == "triangles" else {
            throw RendererAssetLoadFailure.unsupportedAsset
        }
        _ = try Self.validatedBufferSizes(vertexCount: vertices.count, indexCount: indices.count)
        var output: [RendererVertex] = []
        output.reserveCapacity(vertices.count)
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for vertex in vertices {
            let position = SIMD3(vertex.px, vertex.py, vertex.pz)
            let normal = SIMD3(vertex.nx, vertex.ny, vertex.nz)
            let normalLength = simd_length(normal)
            guard position.x.isFinite, position.y.isFinite, position.z.isFinite,
                  normal.x.isFinite, normal.y.isFinite, normal.z.isFinite,
                  abs(position.x) <= 0.4, abs(position.z) <= 0.4,
                  position.x * position.x + position.z * position.z <= 0.16,
                  position.y >= 0, position.y <= 1.8,
                  normalLength.isFinite, abs(normalLength - 1) <= 0.001 else {
                throw RendererAssetLoadFailure.invalidGeometry
            }
            output.append(RendererVertex(position: position, normal: normal))
            minimum = simd_min(minimum, position)
            maximum = simd_max(maximum, position)
        }
        var validatedIndices: [UInt16] = []
        validatedIndices.reserveCapacity(indices.count)
        for index in indices {
            guard index < UInt32(vertices.count), let value = UInt16(exactly: index) else {
                throw RendererAssetLoadFailure.invalidGeometry
            }
            validatedIndices.append(value)
        }
        for index in stride(from: 0, to: validatedIndices.count, by: 3) {
            let a = output[Int(validatedIndices[index])]
            let b = output[Int(validatedIndices[index + 1])]
            let c = output[Int(validatedIndices[index + 2])]
            let cross = simd_cross(b.position - a.position, c.position - a.position)
            let squaredArea = simd_length_squared(cross)
            guard squaredArea.isFinite, squaredArea > 1e-10 else {
                throw RendererAssetLoadFailure.invalidGeometry
            }
            let faceNormal = cross / sqrt(squaredArea)
            guard simd_dot(faceNormal, a.normal) > 0.9,
                  simd_dot(faceNormal, b.normal) > 0.9,
                  simd_dot(faceNormal, c.normal) > 0.9 else {
                throw RendererAssetLoadFailure.invalidGeometry
            }
        }
        let extent = maximum - minimum
        guard simd_distance(minimum, SIMD3(-0.29, 0.84, -0.16)) <= 1e-5,
              simd_distance(maximum, SIMD3(0.29, 1.43, 0.215)) <= 1e-5,
              extent.x > 0, extent.y > 0, extent.z > 0 else {
            throw RendererAssetLoadFailure.invalidGeometry
        }
        return RendererMesh(vertices: output, indices: validatedIndices, minimum: minimum, maximum: maximum)
    }
}

private struct MeshPackageField: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireMeshFields<Key: CodingKey & RawRepresentable>(
    _ decoder: Decoder, type: Key.Type, count: Int
) throws where Key.RawValue == String {
    let values = try decoder.container(keyedBy: MeshPackageField.self)
    let fields = values.allKeys
    guard fields.count == count, fields.allSatisfy({ Key(rawValue: $0.stringValue) != nil }) else {
        throw RendererAssetLoadFailure.malformedPackage
    }
}

#endif
