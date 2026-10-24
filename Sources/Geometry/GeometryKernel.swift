#if DEBUG
import Foundation

/// Scalar spatial contract, not a scanner API. Only the file-sealed fixed-fixture
/// factory can mint reconstruction authorization; source labels alone cannot.
enum GeometryInputSource: Equatable, Sendable { case reviewedSynthetic, scanner, unknown }
enum GeometryInputUnits: Equatable, Sendable { case metres, centimetres, unknown }
enum GeometryInputOrientation: Equatable, Sendable { case rightHandedYUpZFrontFloorCentred, unknown }
enum GeometryInputRole: Hashable, Sendable { case frontAndSideExtents, frontOnly, sideOnly, unknown }
enum GeometryInputAvailability: Equatable, Sendable { case observed, unavailable }
enum GeometryInputQuality: Equatable, Sendable { case authoredSynthetic, insufficient, unknown }
enum GeometryInputCapability: Equatable, Sendable { case openSectionLoftV1, unknown }
enum GeometryRegion: Equatable, Sendable { case syntheticSectionSurface, aboveSections, belowSections, head, limbs }
fileprivate enum GeometryAuthorization: Equatable, Sendable { case reviewedFixture(GeometryFixtureID) }

struct GeometrySectionInput: Sendable {
    let heightMetres: Float
    /// Half-width observed from the front-facing extent.
    let halfWidthMetres: Float
    /// Half-depth observed independently from the side-facing extent.
    let halfDepthMetres: Float
    let role: GeometryInputRole
    let availability: GeometryInputAvailability
    let quality: GeometryInputQuality
    let region: GeometryRegion

    init(heightMetres: Float, halfWidthMetres: Float, halfDepthMetres: Float,
         role: GeometryInputRole = .frontAndSideExtents,
         availability: GeometryInputAvailability = .observed, quality: GeometryInputQuality = .authoredSynthetic,
         region: GeometryRegion = .syntheticSectionSurface) {
        self.heightMetres = heightMetres
        self.halfWidthMetres = halfWidthMetres
        self.halfDepthMetres = halfDepthMetres
        self.role = role
        self.availability = availability
        self.quality = quality
        self.region = region
    }
}

struct GeometryInput: Sendable {
    let schemaVersion: Int
    let source: GeometryInputSource
    let units: GeometryInputUnits
    let orientation: GeometryInputOrientation
    let metresPerUnit: Float
    let capability: GeometryInputCapability
    let sections: [GeometrySectionInput]
    let unknownRegionsMetres: [ClosedRange<Float>]
    let radialSegments: Int
    fileprivate let authorization: GeometryAuthorization?

    init(schemaVersion: Int = 1, source: GeometryInputSource = .unknown,
         units: GeometryInputUnits = .metres,
         orientation: GeometryInputOrientation = .rightHandedYUpZFrontFloorCentred,
         sections: [GeometrySectionInput], unknownRegionsMetres: [ClosedRange<Float>] = [],
         radialSegments: Int = 24, metresPerUnit: Float = 1,
         capability: GeometryInputCapability = .openSectionLoftV1) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.units = units
        self.orientation = orientation
        self.sections = sections
        self.metresPerUnit = metresPerUnit
        self.capability = capability
        self.unknownRegionsMetres = unknownRegionsMetres
        self.radialSegments = radialSegments
        self.authorization = nil
    }

    fileprivate init(fixture: GeometryFixtureID, sections: [GeometrySectionInput], unknownRegionsMetres: [ClosedRange<Float>] = []) {
        self.schemaVersion = 1
        self.source = .reviewedSynthetic
        self.units = .metres
        self.orientation = .rightHandedYUpZFrontFloorCentred
        self.metresPerUnit = 1
        self.capability = .openSectionLoftV1
        self.sections = sections
        self.unknownRegionsMetres = unknownRegionsMetres
        self.radialSegments = 24
        self.authorization = .reviewedFixture(fixture)
    }
}
/// Authorization is minted only by the fixed reviewed fixture factory in GeometryKernel.swift.
struct GeometryResult: Equatable, Sendable {
    let mesh: GeometryMesh
    let fixture: GeometryFixtureID
    let schemaVersion: Int
    let algorithm: GeometryAlgorithm
    let provenance: GeometryProvenance
    let observedSectionHeightsMetres: [Float]
    let unknownRegionsMetres: [ClosedRange<Float>]
    let interpolation: GeometryInterpolation
    let unknownRegionPolicy: GeometryUnknownRegionPolicy
    let validationStatus: GeometryValidationStatus
    let rendererCapability: GeometryRendererCapability
    let coordinateConvention = "right-handed:+Y-up:+Z-forward:floor-centred"
    let metresPerUnit: Float = 1
    let unsupportedRegions: [GeometryRegion] = [.aboveSections, .belowSections, .head, .limbs]
    fileprivate let authorization: GeometryAuthorization

    fileprivate init(
        mesh: GeometryMesh,
        fixture: GeometryFixtureID,
        schemaVersion: Int,
        algorithm: GeometryAlgorithm,
        provenance: GeometryProvenance,
        observedSectionHeightsMetres: [Float],
        unknownRegionsMetres: [ClosedRange<Float>],
        interpolation: GeometryInterpolation,
        unknownRegionPolicy: GeometryUnknownRegionPolicy,
        validationStatus: GeometryValidationStatus,
        rendererCapability: GeometryRendererCapability,
        authorization: GeometryAuthorization
    ) {
        self.mesh = mesh
        self.fixture = fixture
        self.schemaVersion = schemaVersion
        self.algorithm = algorithm
        self.provenance = provenance
        self.observedSectionHeightsMetres = observedSectionHeightsMetres
        self.unknownRegionsMetres = unknownRegionsMetres
        self.interpolation = interpolation
        self.unknownRegionPolicy = unknownRegionPolicy
        self.validationStatus = validationStatus
        self.rendererCapability = rendererCapability
        self.authorization = authorization
    }

    func validate() throws {
        guard authorization == .reviewedFixture(fixture),
              schemaVersion == 1,
              algorithm == .openEllipticalLoftV1,
              provenance == .reviewedSyntheticFixture,
              interpolation == .betweenObservedSectionsOnly,
              unknownRegionPolicy == .unmodeledAndUnbridged,
              validationStatus == .validated,
              rendererCapability == .neutralIllustrationOnly,
              observedSectionHeightsMetres.count >= GeometryKernel.minimumSections,
              observedSectionHeightsMetres.count <= GeometryKernel.maximumSections,
              observedSectionHeightsMetres.allSatisfy(\.isFinite),
              zip(observedSectionHeightsMetres, observedSectionHeightsMetres.dropFirst()).allSatisfy({ $0 < $1 }),
              unknownRegionsMetres.isEmpty
        else { throw GeometryFailure.invalidMetadata }
        try mesh.validate()
    }
}

enum GeometryKernel {
    static let currentInputSchema = 1
    static let minimumSections = 4
    static let maximumSections = 32
    static let maximumRadialSegments = 48
    static let maximumSectionGapMetres: Float = 0.30
    static let minimumExtentMetres: Float = 0.01

    static func preflight(sectionCount: Int, radialSegments: Int) throws {
        guard sectionCount >= minimumSections else { throw GeometryFailure.insufficientSections }
        guard sectionCount <= maximumSections,
              radialSegments >= 3, radialSegments <= maximumRadialSegments else {
            throw GeometryFailure.resourceLimit
        }
        // One ring per section, two triangles per quad, three indices per triangle.
        let (vertices, vertexOverflow) = sectionCount.multipliedReportingOverflow(by: radialSegments)
        let (ringPairCount, pairOverflow) = (sectionCount - 1).multipliedReportingOverflow(by: 6)
        let (indices, indexOverflow) = ringPairCount.multipliedReportingOverflow(by: radialSegments)
        let (payload, payloadOverflow) = vertices.multipliedReportingOverflow(by: MemoryLayout<GeometryVertex>.stride)
        let (indexBytes, indexBytesOverflow) = indices.multipliedReportingOverflow(by: MemoryLayout<UInt16>.stride)
        let (totalBytes, totalOverflow) = payload.addingReportingOverflow(indexBytes)
        guard !vertexOverflow, !pairOverflow, !indexOverflow, !payloadOverflow,
              !indexBytesOverflow, !totalOverflow,
              vertices <= GeometryMesh.maximumVertices,
              indices <= GeometryMesh.maximumIndices,
              totalBytes <= GeometryMesh.maximumPayloadBytes,
              vertices <= Int(UInt16.max) + 1 else { throw GeometryFailure.resourceLimit }
    }

    /// Scanner admission is intentionally unavailable. A future authorized adapter must provide
    /// calibrated metre units in the exact right-handed, +Y-up, +Z-front, floor-centred frame;
    /// distinct front and side views with person-associated same-attempt evidence;
    /// strictly increasing observed heights in [0, 1.8]m; independent front half-width
    /// and side half-depth in [0.01, 0.4]m; no duplicate/unknown sections; gaps <=0.30m.
    /// Numerical acceptance is NOT physical evidence validation. A future adapter
    /// must separately establish calibration, continuity and repeatability; this
    /// validator cannot mint authorization or promote existing capture candidates.
    /// Validator is exposed to @testable consumers for adversarial DTO tests; it never authorizes output.
    static func validate(input: GeometryInput) throws {
        guard input.schemaVersion == currentInputSchema, input.capability == .openSectionLoftV1 else {
            throw GeometryFailure.unsupportedSchema
        }
        guard input.units == .metres, input.metresPerUnit.isFinite, input.metresPerUnit == 1 else {
            throw GeometryFailure.unsupportedUnits
        }
        guard input.orientation == .rightHandedYUpZFrontFloorCentred else { throw GeometryFailure.unsupportedOrientation }
        guard input.source == .reviewedSynthetic else { throw GeometryFailure.unverifiedSource }
        try preflight(sectionCount: input.sections.count, radialSegments: input.radialSegments)
        // S2A chooses rejection instead of inventing or bridging a missing region.
        guard input.unknownRegionsMetres.isEmpty else { throw GeometryFailure.unavailableObservation }
        guard input.sections.allSatisfy({ $0.availability == .observed }) else { throw GeometryFailure.unavailableObservation }
        guard input.sections.allSatisfy({ $0.role == .frontAndSideExtents && $0.region == .syntheticSectionSurface }) else {
            throw GeometryFailure.invalidRole
        }
        for section in input.sections {
            guard section.heightMetres.isFinite, section.halfWidthMetres.isFinite, section.halfDepthMetres.isFinite else {
                throw GeometryFailure.nonFiniteValue
            }
            guard section.quality == .authoredSynthetic else { throw GeometryFailure.invalidQuality }
            guard section.heightMetres >= 0, section.heightMetres <= 1.8,
                  section.halfWidthMetres >= minimumExtentMetres, section.halfDepthMetres >= minimumExtentMetres,
                  section.halfWidthMetres <= 0.4, section.halfDepthMetres <= 0.4 else {
                throw GeometryFailure.invalidDimensions
            }
        }
        for index in 1..<input.sections.count {
            let previousSection = input.sections[index - 1]
            let currentSection = input.sections[index]
            let previous = previousSection.heightMetres
            let current = currentSection.heightMetres
            guard current > previous else {
                throw current == previous ? GeometryFailure.duplicatedSection : GeometryFailure.unorderedSections
            }
            guard current - previous >= 0.01, current - previous <= maximumSectionGapMetres,
                  abs(currentSection.halfWidthMetres - previousSection.halfWidthMetres) <= current - previous,
                  abs(currentSection.halfDepthMetres - previousSection.halfDepthMetres) <= current - previous else {
                throw GeometryFailure.discontinuousSections
            }
        }
    }

    static func generate(_ input: GeometryInput, cancellationCheck: () -> Bool = { false }) throws -> GeometryResult {
        try validate(input: input)
        guard let authorization = input.authorization,
              case .reviewedFixture(let fixture) = authorization else { throw GeometryFailure.unverifiedSource }
        try checkCancellation(cancellationCheck)
        let sections = input.sections
        // Every ring is an authored synthetic section. Only the lateral surface
        // between adjacent rings is interpolated. No caps or unknown regions.
        let radial = input.radialSegments
        var vertices: [GeometryVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(sections.count * radial)
        indices.reserveCapacity((sections.count - 1) * radial * 6)
        for section in sections {
            try checkCancellation(cancellationCheck)
            for segment in 0..<radial {
                let theta = 2 * Float.pi * Float(segment) / Float(radial)
                vertices.append(GeometryVertex(
                    position: SIMD3<Float>(section.halfWidthMetres * cos(theta), section.heightMetres,
                                           section.halfDepthMetres * sin(theta)),
                    normal: .zero
                ))
            }
        }
        for ring in 0..<(sections.count - 1) {
            try checkCancellation(cancellationCheck)
            for segment in 0..<radial {
                let next = (segment + 1) % radial
                let lower = ring * radial
                let upper = lower + radial
                indices.append(UInt16(lower + segment))
                indices.append(UInt16(upper + segment))
                indices.append(UInt16(lower + next))
                indices.append(UInt16(upper + segment))
                indices.append(UInt16(upper + next))
                indices.append(UInt16(lower + next))
            }
        }
        // Area-weighted smooth normals include the changing section slope.
        // Accumulate directly into output vertices: no second full mesh allocation.
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
        // Exact bounds come only from emitted, observed section rings.
        var minimum = SIMD3<Float>(repeating: .infinity)
        var maximum = SIMD3<Float>(repeating: -.infinity)
        for vertex in vertices {
            minimum = SIMD3<Float>(min(minimum.x, vertex.position.x), min(minimum.y, vertex.position.y), min(minimum.z, vertex.position.z))
            maximum = SIMD3<Float>(max(maximum.x, vertex.position.x), max(maximum.y, vertex.position.y), max(maximum.z, vertex.position.z))
        }
        let mesh = GeometryMesh(vertices: vertices, indices: indices, minimum: minimum, maximum: maximum)
        try mesh.validate()
        try checkCancellation(cancellationCheck)
        return GeometryResult(
            mesh: mesh, fixture: fixture, schemaVersion: 1, algorithm: .openEllipticalLoftV1,
            provenance: .reviewedSyntheticFixture,
            observedSectionHeightsMetres: sections.map(\.heightMetres),
            unknownRegionsMetres: input.unknownRegionsMetres,
            interpolation: .betweenObservedSectionsOnly,
            unknownRegionPolicy: .unmodeledAndUnbridged,
            validationStatus: .validated,
            rendererCapability: .neutralIllustrationOnly,
            authorization: authorization
        )
    }

    static func validate(mesh: GeometryMesh) throws {
        guard mesh.vertices.count >= 3, mesh.vertices.count <= GeometryMesh.maximumVertices,
              mesh.indices.count >= 3, mesh.indices.count <= GeometryMesh.maximumIndices,
              mesh.indices.count.isMultiple(of: 3) else { throw GeometryFailure.invalidMesh }
        let (vertexBytes, vertexOverflow) = mesh.vertices.count.multipliedReportingOverflow(by: MemoryLayout<GeometryVertex>.stride)
        let (indexBytes, indexOverflow) = mesh.indices.count.multipliedReportingOverflow(by: MemoryLayout<UInt16>.stride)
        let (bytes, totalOverflow) = vertexBytes.addingReportingOverflow(indexBytes)
        guard !vertexOverflow, !indexOverflow, !totalOverflow, bytes <= GeometryMesh.maximumPayloadBytes else { throw GeometryFailure.resourceLimit }
        guard finite(mesh.minimum), finite(mesh.maximum), mesh.minimum.x <= mesh.maximum.x,
              mesh.minimum.y <= mesh.maximum.y, mesh.minimum.z <= mesh.maximum.z else { throw GeometryFailure.invalidMesh }
        var actualMinimum = SIMD3<Float>(repeating: .infinity)
        var actualMaximum = SIMD3<Float>(repeating: -.infinity)
        for vertex in mesh.vertices {
            guard finite(vertex.position) else { throw GeometryFailure.nonFiniteValue }
            actualMinimum = SIMD3<Float>(min(actualMinimum.x, vertex.position.x), min(actualMinimum.y, vertex.position.y), min(actualMinimum.z, vertex.position.z))
            actualMaximum = SIMD3<Float>(max(actualMaximum.x, vertex.position.x), max(actualMaximum.y, vertex.position.y), max(actualMaximum.z, vertex.position.z))
        }
        guard close(mesh.minimum, actualMinimum), close(mesh.maximum, actualMaximum) else { throw GeometryFailure.invalidMesh }
        for vertex in mesh.vertices {
            guard finite(vertex.position), finite(vertex.normal) else { throw GeometryFailure.nonFiniteValue }
            let norm = length(vertex.normal)
            guard abs(norm - 1) <= 0.01,
                  abs(vertex.position.x) <= 0.4, vertex.position.y >= 0, vertex.position.y <= 1.8,
                  abs(vertex.position.z) <= 0.4 else { throw GeometryFailure.invalidMesh }
            guard dot(vertex.normal, SIMD3<Float>(vertex.position.x, 0, vertex.position.z)) > 0 else {
                throw GeometryFailure.invalidMesh
            }
            guard vertex.position.x >= mesh.minimum.x - 0.0001, vertex.position.x <= mesh.maximum.x + 0.0001,
                  vertex.position.y >= mesh.minimum.y - 0.0001, vertex.position.y <= mesh.maximum.y + 0.0001,
                  vertex.position.z >= mesh.minimum.z - 0.0001, vertex.position.z <= mesh.maximum.z + 0.0001 else { throw GeometryFailure.invalidMesh }
        }
        for offset in stride(from: 0, to: mesh.indices.count, by: 3) {
            let ia = Int(mesh.indices[offset]), ib = Int(mesh.indices[offset + 1]), ic = Int(mesh.indices[offset + 2])
            guard ia < mesh.vertices.count, ib < mesh.vertices.count, ic < mesh.vertices.count else { throw GeometryFailure.invalidMesh }
            let a = mesh.vertices[ia].position, b = mesh.vertices[ib].position, c = mesh.vertices[ic].position
            let ab = b - a, ac = c - a
            let cross = SIMD3<Float>(ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z, ab.x * ac.y - ab.y * ac.x)
            guard length(cross) > 1e-8 else { throw GeometryFailure.invalidMesh }
            let averageNormal = mesh.vertices[ia].normal + mesh.vertices[ib].normal + mesh.vertices[ic].normal
            guard dot(cross, averageNormal) > 0 else { throw GeometryFailure.invalidMesh }
        }
    }

    static func reviewedFixture(_ fixture: GeometryFixtureID) throws -> GeometryInput {
        let heights: [Float] = [0.45, 0.62, 0.79, 0.96, 1.13, 1.30]
        let profile: [(Float, Float)]
        switch fixture {
        case .surfaceA: profile = [(0.15,0.10),(0.18,0.12),(0.20,0.13),(0.19,0.12),(0.16,0.10),(0.12,0.08)]
        case .surfaceB: profile = [(0.11,0.16),(0.14,0.18),(0.16,0.19),(0.15,0.18),(0.13,0.15),(0.10,0.12)]
        case .missingRegion: profile = [(0.14,0.10),(0.17,0.11),(0.18,0.12),(0.17,0.11),(0.15,0.10),(0.12,0.08)]
        case .invalidGeometry: profile = [(0.15,0.10),(0.18,0.12),(0.20,0.13),(0.19,0.12),(0.16,0.10),(0.12,0.08)]
        case .unverifiedSource: profile = [(0.15,0.10),(0.18,0.12),(0.20,0.13),(0.19,0.12),(0.16,0.10),(0.12,0.08)]
        }
        var sections = zip(heights, profile).map { GeometrySectionInput(heightMetres: $0.0, halfWidthMetres: $0.1.0, halfDepthMetres: $0.1.1) }
        if fixture == .unverifiedSource {
            // Authored nonpersonal negative fixture with scanner-shaped scalars:
            // neither its source tag nor plausible numbers can mint authorization.
            return GeometryInput(source: .scanner, sections: sections)
        }
        var unknown: [ClosedRange<Float>] = []
        if fixture == .missingRegion {
            // A declared required unknown interval rejects the whole demonstration.
            unknown = [0.79...0.96]
        } else if fixture == .invalidGeometry {
            sections[2] = GeometrySectionInput(heightMetres: .nan, halfWidthMetres: 0.2, halfDepthMetres: 0.1)
        }
        return GeometryInput(fixture: fixture, sections: sections, unknownRegionsMetres: unknown)
    }

    private static func checkCancellation(_ check: () -> Bool) throws {
        if check() { throw GeometryFailure.cancelled }
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func length(_ value: SIMD3<Float>) -> Float { sqrt(dot(value, value)) }
    private static func dot(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float { lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z }
    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
    private static func close(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        abs(lhs.x - rhs.x) <= 0.0001 && abs(lhs.y - rhs.y) <= 0.0001 && abs(lhs.z - rhs.z) <= 0.0001
    }
}
#endif
