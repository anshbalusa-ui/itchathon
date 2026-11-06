#if DEBUG
import CryptoKit
import Foundation

enum SyntheticArtifactFailure: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case corruptArtifact
    case unsupportedVersion
    case incompatibleArtifact
    case unauthorizedSource
    case resourceLimit
    case invalidFileKind
    case storageFailure
    case conflict
    case durabilityUncertain

    var errorDescription: String? {
        switch self {
        case .cancelled: return "The synthetic artifact operation was cancelled."
        case .corruptArtifact: return "The synthetic artifact is damaged or invalid."
        case .unsupportedVersion: return "The synthetic artifact version is not supported."
        case .incompatibleArtifact: return "The synthetic artifact is incompatible with this renderer."
        case .unauthorizedSource: return "Only reviewed synthetic fixtures can be admitted."
        case .resourceLimit: return "The synthetic artifact exceeds safe resource limits."
        case .invalidFileKind: return "The synthetic artifact file kind is invalid."
        case .storageFailure: return "The local synthetic artifact operation could not complete."
        case .conflict: return "The synthetic artifact conflicts with another operation."
        case .durabilityUncertain: return "Local storage changed, but durable completion could not be confirmed. Load to check the current artifact."
        }
    }
}

struct SyntheticArtifactIdentity: Equatable, Sendable {
    let fixture: GeometryFixtureID
    let revision: Int
    let artifactID: String
    let contentDigest: String
}

/// A codec-sealed artifact. Its mesh is the data decoded from disk, not regenerated output.
struct VerifiedSyntheticArtifact: Equatable, Sendable {
    let mesh: GeometryMesh
    let identity: SyntheticArtifactIdentity
    var fixture: GeometryFixtureID { identity.fixture }

    fileprivate init(mesh: GeometryMesh, identity: SyntheticArtifactIdentity) {
        self.mesh = mesh
        self.identity = identity
    }

    func validate() throws {
        guard (fixture == .surfaceA || fixture == .surfaceB),
              identity.revision == SyntheticArtifactCodec.artifactRevision,
              SyntheticArtifactCodec.isValidArtifactID(identity.artifactID),
              SyntheticArtifactCodec.isDigest(identity.contentDigest) else {
            throw SyntheticArtifactFailure.incompatibleArtifact
        }
        try mesh.validate()
        // Immutable decoded arrays and identity can only enter through admission.
        // Canonical regeneration/comparison occurs once off-main in decode().
    }
}

/// Version 1 is a bounded UTF-8 JSON metadata envelope containing base64 of a fixed-width binary mesh.
/// Payload order: vertex count, index count (UInt32 LE); each vertex position xyz and normal xyz
/// as IEEE-754 Float32 LE; indices as UInt16 LE; minimum xyz and maximum xyz as Float32 LE.
enum SyntheticArtifactCodec {
    static let maximumFileBytes = 262_144
    static let maximumPayloadBytes = GeometryMesh.maximumPayloadBytes
    static let artifactRevision = 1

    private static let formatVersion = 1
    private static let meshSchema = 1
    private static let coordinateConvention = "right-handed:+Y-up:+Z-forward:floor-centred"
    private static let algorithmID = "open-elliptical-loft-v1"
    private static let provenance = "reviewed-synthetic-fixture"
    private static let interpolation = "between-observed-sections-only"
    private static let unknownRegionPolicy = "unmodeled-and-unbridged"
    private static let role = "front-and-side"
    private static let rendererCapability = "neutral-illustration-only"
    private static let validationStatus = "validated"

    private struct VersionHeader: Decodable {
        let formatVersion: Int
        let artifactRevision: Int
    }

    private struct Envelope: Codable {
        let formatVersion: Int
        let artifactRevision: Int
        let artifactID: String
        let fixture: String
        let fixtureRevision: Int
        let schemaVersion: Int
        let algorithm: String
        let algorithmRevision: Int
        let meshSchema: Int
        let coordinateConvention: String
        let metresPerUnit: Float
        let provenance: String
        let role: String
        let interpolation: String
        let unknownRegionPolicy: String
        let validationStatus: String
        let rendererCapability: String
        let observedSectionHeightsMetres: [Float]
        let unknownRegionsMetres: [ClosedRangeRecord]
        let unsupportedRegions: [String]
        let vertexCount: Int
        let indexCount: Int
        let minimum: [Float]
        let maximum: [Float]
        let payload: Data
        let digest: String
    }

    private struct ClosedRangeRecord: Codable {
        let lower: Float
        let upper: Float
    }

    static func encode(_ geometry: GeometryResult) throws -> Data {
        try encodeWithIdentity(geometry).data
    }

    static func encodeWithIdentity(_ geometry: GeometryResult) throws -> (data: Data, identity: SyntheticArtifactIdentity) {
        try checkCancellation()
        do { try geometry.validate() }
        catch { throw SyntheticArtifactFailure.unauthorizedSource }
        guard geometry.fixture == .surfaceA || geometry.fixture == .surfaceB else {
            throw SyntheticArtifactFailure.unauthorizedSource
        }
        guard hasSupportedMetadata(geometry) else { throw SyntheticArtifactFailure.incompatibleArtifact }
        let payload = try encodeMesh(geometry.mesh)
        let digest = sha256(payload)
        let envelope = Envelope(
            formatVersion: formatVersion, artifactRevision: artifactRevision,
            artifactID: UUID().uuidString.lowercased(), fixture: geometry.fixture.rawValue,
            fixtureRevision: 1, schemaVersion: geometry.schemaVersion,
            algorithm: geometry.algorithm.rawValue, algorithmRevision: 1, meshSchema: meshSchema,
            coordinateConvention: geometry.coordinateConvention, metresPerUnit: geometry.metresPerUnit,
            provenance: geometry.provenance.rawValue, role: role,
            interpolation: geometry.interpolation.rawValue, unknownRegionPolicy: geometry.unknownRegionPolicy.rawValue,
            validationStatus: geometry.validationStatus.rawValue,
            rendererCapability: geometry.rendererCapability.rawValue,
            observedSectionHeightsMetres: geometry.observedSectionHeightsMetres,
            unknownRegionsMetres: geometry.unknownRegionsMetres.map { ClosedRangeRecord(lower: $0.lowerBound, upper: $0.upperBound) },
            unsupportedRegions: ["aboveSections", "belowSections", "head", "limbs"],
            vertexCount: geometry.mesh.vertices.count, indexCount: geometry.mesh.indices.count,
            minimum: vector(geometry.mesh.minimum), maximum: vector(geometry.mesh.maximum),
            payload: payload, digest: digest
        )
        let data: Data
        do { data = try JSONEncoder().encode(envelope) }
        catch { throw SyntheticArtifactFailure.storageFailure }
        guard data.count <= maximumFileBytes else { throw SyntheticArtifactFailure.resourceLimit }
        try checkCancellation()
        return (data, SyntheticArtifactIdentity(fixture: geometry.fixture, revision: artifactRevision,
                                               artifactID: envelope.artifactID, contentDigest: digest))
    }

    static func decode(_ data: Data) throws -> VerifiedSyntheticArtifact {
        try checkCancellation()
        guard data.count <= maximumFileBytes else { throw SyntheticArtifactFailure.resourceLimit }
        guard !data.isEmpty else { throw SyntheticArtifactFailure.corruptArtifact }
        let header: VersionHeader
        do { header = try JSONDecoder().decode(VersionHeader.self, from: data) }
        catch { throw SyntheticArtifactFailure.corruptArtifact }
        guard header.formatVersion == formatVersion, header.artifactRevision == artifactRevision else {
            throw SyntheticArtifactFailure.unsupportedVersion
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw SyntheticArtifactFailure.corruptArtifact }
        try checkCancellation()
        guard envelope.formatVersion == formatVersion, envelope.artifactRevision == artifactRevision else {
            throw SyntheticArtifactFailure.unsupportedVersion
        }
        guard envelope.fixture == GeometryFixtureID.surfaceA.rawValue || envelope.fixture == GeometryFixtureID.surfaceB.rawValue else {
            throw SyntheticArtifactFailure.unauthorizedSource
        }
        guard envelope.fixtureRevision == 1, envelope.schemaVersion == 1,
              envelope.algorithm == algorithmID, envelope.algorithmRevision == 1,
              envelope.meshSchema == meshSchema else { throw SyntheticArtifactFailure.unsupportedVersion }
        guard envelope.coordinateConvention == coordinateConvention, envelope.metresPerUnit == 1,
              envelope.provenance == provenance else { throw SyntheticArtifactFailure.unauthorizedSource }
        guard envelope.role == role, envelope.interpolation == interpolation,
              envelope.unknownRegionPolicy == unknownRegionPolicy,
              envelope.validationStatus == validationStatus,
              envelope.rendererCapability == rendererCapability else { throw SyntheticArtifactFailure.incompatibleArtifact }
        guard isValidArtifactID(envelope.artifactID), isDigest(envelope.digest) else {
            throw SyntheticArtifactFailure.corruptArtifact
        }
        guard envelope.vertexCount >= 3, envelope.vertexCount <= GeometryMesh.maximumVertices,
              envelope.indexCount >= 3, envelope.indexCount <= GeometryMesh.maximumIndices,
              envelope.indexCount.isMultiple(of: 3),
              envelope.observedSectionHeightsMetres.count >= GeometryKernel.minimumSections,
              envelope.observedSectionHeightsMetres.count <= GeometryKernel.maximumSections,
              envelope.unknownRegionsMetres.isEmpty,
              envelope.unsupportedRegions == ["aboveSections", "belowSections", "head", "limbs"],
              envelope.minimum.count == 3, envelope.maximum.count == 3 else {
            throw SyntheticArtifactFailure.resourceLimit
        }
        let expectedSize = try checkedPayloadSize(vertices: envelope.vertexCount, indices: envelope.indexCount)
        guard envelope.payload.count == expectedSize, envelope.payload.count <= maximumPayloadBytes else {
            throw SyntheticArtifactFailure.corruptArtifact
        }
        guard sha256(envelope.payload) == envelope.digest else { throw SyntheticArtifactFailure.corruptArtifact }
        try checkCancellation()
        let mesh = try decodeMesh(envelope.payload, vertexCount: envelope.vertexCount, indexCount: envelope.indexCount)
        guard vector(mesh.minimum) == envelope.minimum, vector(mesh.maximum) == envelope.maximum else {
            throw SyntheticArtifactFailure.corruptArtifact
        }
        do { try mesh.validate() }
        catch { throw SyntheticArtifactFailure.corruptArtifact }
        let fixture = envelope.fixture == GeometryFixtureID.surfaceA.rawValue ? GeometryFixtureID.surfaceA : .surfaceB
        let expected = try regenerate(fixture)
        guard envelope.observedSectionHeightsMetres == expected.observedSectionHeightsMetres,
              mesh == expected.mesh else { throw SyntheticArtifactFailure.incompatibleArtifact }
        try checkCancellation()
        return VerifiedSyntheticArtifact(mesh: mesh,
            identity: SyntheticArtifactIdentity(fixture: fixture, revision: artifactRevision,
                                               artifactID: envelope.artifactID, contentDigest: envelope.digest))
    }

    fileprivate static func regenerate(_ fixture: GeometryFixtureID) throws -> GeometryResult {
        guard fixture == .surfaceA || fixture == .surfaceB else { throw SyntheticArtifactFailure.unauthorizedSource }
        try checkCancellation()
        do {
            let input = try GeometryKernel.reviewedFixture(fixture)
            let result = try GeometryKernel.generate(input, cancellationCheck: { Task.isCancelled })
            try result.validate()
            return result
        } catch GeometryFailure.cancelled { throw SyntheticArtifactFailure.cancelled }
        catch { throw SyntheticArtifactFailure.incompatibleArtifact }
    }

    fileprivate static func isValidArtifactID(_ value: String) -> Bool {
        guard value.count == 36 else { return false }
        return UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    fileprivate static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func hasSupportedMetadata(_ result: GeometryResult) -> Bool {
        result.schemaVersion == 1 && result.algorithm == .openEllipticalLoftV1 &&
        result.provenance == .reviewedSyntheticFixture && result.observedSectionHeightsMetres.count == 6 &&
        result.unknownRegionsMetres.isEmpty && result.interpolation == .betweenObservedSectionsOnly &&
        result.unknownRegionPolicy == .unmodeledAndUnbridged && result.validationStatus == .validated &&
        result.rendererCapability == .neutralIllustrationOnly && result.coordinateConvention == coordinateConvention &&
        result.metresPerUnit == 1
    }

    private static func encodeMesh(_ mesh: GeometryMesh) throws -> Data {
        let size = try checkedPayloadSize(vertices: mesh.vertices.count, indices: mesh.indices.count)
        guard size <= maximumPayloadBytes else { throw SyntheticArtifactFailure.resourceLimit }
        var data = Data(); data.reserveCapacity(size)
        append(UInt32(mesh.vertices.count), to: &data); append(UInt32(mesh.indices.count), to: &data)
        for vertex in mesh.vertices {
            append(vertex.position.x.bitPattern, to: &data); append(vertex.position.y.bitPattern, to: &data)
            append(vertex.position.z.bitPattern, to: &data); append(vertex.normal.x.bitPattern, to: &data)
            append(vertex.normal.y.bitPattern, to: &data); append(vertex.normal.z.bitPattern, to: &data)
        }
        for index in mesh.indices { append(index, to: &data) }
        append(mesh.minimum.x.bitPattern, to: &data); append(mesh.minimum.y.bitPattern, to: &data)
        append(mesh.minimum.z.bitPattern, to: &data); append(mesh.maximum.x.bitPattern, to: &data)
        append(mesh.maximum.y.bitPattern, to: &data); append(mesh.maximum.z.bitPattern, to: &data)
        return data
    }

    private static func decodeMesh(_ data: Data, vertexCount: Int, indexCount: Int) throws -> GeometryMesh {
        var cursor = 0
        guard Int(try readUInt32(data, cursor: &cursor)) == vertexCount,
              Int(try readUInt32(data, cursor: &cursor)) == indexCount else { throw SyntheticArtifactFailure.corruptArtifact }
        var vertices: [GeometryVertex] = []; vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            let p = try readVector(data, cursor: &cursor), n = try readVector(data, cursor: &cursor)
            vertices.append(GeometryVertex(position: p, normal: n))
        }
        var indices: [UInt16] = []; indices.reserveCapacity(indexCount)
        for _ in 0..<indexCount { indices.append(try readUInt16(data, cursor: &cursor)) }
        let minimum = try readVector(data, cursor: &cursor), maximum = try readVector(data, cursor: &cursor)
        guard cursor == data.count else { throw SyntheticArtifactFailure.corruptArtifact }
        return GeometryMesh(vertices: vertices, indices: indices, minimum: minimum, maximum: maximum)
    }

    private static func checkedPayloadSize(vertices: Int, indices: Int) throws -> Int {
        let (vertexBytes, a) = vertices.multipliedReportingOverflow(by: 24)
        let (indexBytes, b) = indices.multipliedReportingOverflow(by: 2)
        let (total, c) = vertexBytes.addingReportingOverflow(indexBytes)
        let (withHeaders, d) = total.addingReportingOverflow(32)
        guard !a, !b, !c, !d, withHeaders <= maximumPayloadBytes else { throw SyntheticArtifactFailure.resourceLimit }
        return withHeaders
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        for shift in stride(from: 0, through: 24, by: 8) { data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }
    private static func append(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8))
    }
    private static func readUInt32(_ data: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor <= data.count - 4 else { throw SyntheticArtifactFailure.corruptArtifact }
        var value: UInt32 = 0
        for shift in stride(from: 0, through: 24, by: 8) { value |= UInt32(data[cursor]) << UInt32(shift); cursor += 1 }
        return value
    }
    private static func readUInt16(_ data: Data, cursor: inout Int) throws -> UInt16 {
        guard cursor <= data.count - 2 else { throw SyntheticArtifactFailure.corruptArtifact }
        let value = UInt16(data[cursor]) | UInt16(data[cursor + 1]) << 8; cursor += 2; return value
    }
    private static func readFloat(_ data: Data, cursor: inout Int) throws -> Float {
        Float(bitPattern: try readUInt32(data, cursor: &cursor))
    }
    private static func readVector(_ data: Data, cursor: inout Int) throws -> SIMD3<Float> {
        SIMD3(try readFloat(data, cursor: &cursor), try readFloat(data, cursor: &cursor), try readFloat(data, cursor: &cursor))
    }
    
    private static func vector(_ value: SIMD3<Float>) -> [Float] { [value.x, value.y, value.z] }
    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func checkCancellation() throws { if Task.isCancelled { throw SyntheticArtifactFailure.cancelled } }
}
#endif
