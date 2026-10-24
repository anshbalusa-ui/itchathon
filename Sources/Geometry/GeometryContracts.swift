#if DEBUG
import Foundation

/// Debug-only synthetic illustration contracts. Nothing here accepts scanner buffers or profile data.
enum GeometryFixtureID: String, CaseIterable, Identifiable, Sendable {
    case surfaceA
    case surfaceB
    case missingRegion
    case invalidGeometry
    case unverifiedSource

    var id: String { rawValue }
    var title: String {
        switch self {
        case .surfaceA: return "Synthetic surface A"
        case .surfaceB: return "Synthetic surface B"
        case .missingRegion: return "Synthetic missing-region rejection"
        case .invalidGeometry: return "Synthetic invalid geometry"
        case .unverifiedSource: return "Synthetic unverified-source rejection"
        }
    }
}

struct GeometryVertex: Equatable, Sendable {
    let position: SIMD3<Float>
    var normal: SIMD3<Float>
}

struct GeometryMesh: Equatable, Sendable {
    let vertices: [GeometryVertex]
    let indices: [UInt16]
    let minimum: SIMD3<Float>
    let maximum: SIMD3<Float>

    /// Renderer-compatible, deliberately conservative allocation ceilings.
    static let maximumVertices = 2_048
    static let maximumIndices = 12_288
    static let maximumPayloadBytes = 131_072

    func validate() throws {
        try GeometryKernel.validate(mesh: self)
    }
}

enum GeometryFailure: Error, Equatable, LocalizedError, Sendable {
    case cancelled
    case graphicsUnavailable
    case invalidFixture
    case unsupportedSchema
    case unsupportedUnits
    case unsupportedOrientation
    case unverifiedSource
    case invalidRole
    case unavailableObservation
    case insufficientSections
    case invalidDimensions
    case nonFiniteValue
    case unorderedSections
    case duplicatedSection
    case discontinuousSections
    case invalidQuality
    case resourceLimit
    case invalidMesh
    case invalidMetadata

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Geometry generation was cancelled."
        case .graphicsUnavailable: return "Geometry rendering is unavailable."
        case .unverifiedSource: return "Unverified scanner candidates and unknown sources are not authorized for this synthetic lab."
        case .unavailableObservation: return "A required synthetic region is missing. No surface was filled in."
        case .insufficientSections: return "There are not enough supported synthetic sections to generate a surface."
        case .nonFiniteValue, .invalidDimensions: return "The synthetic observations contain invalid spatial values."
        case .unsupportedSchema: return "This geometry schema or reconstruction capability is unsupported."
        case .unsupportedUnits, .unsupportedOrientation: return "The spatial units, scale or coordinate convention are unsupported."
        case .invalidRole, .invalidQuality: return "Independent authored front and side observations are required."
        case .unorderedSections, .duplicatedSection, .discontinuousSections: return "The synthetic sections are duplicated, unordered or incompatible."
        case .resourceLimit: return "The requested geometry exceeds the bounded reconstruction limits."
        case .invalidMesh, .invalidMetadata, .invalidFixture: return "The synthetic surface failed validation and cannot be displayed."
        }
    }
}

protocol GeometryGenerating: Sendable {
    func generate(_ fixture: GeometryFixtureID) async throws -> GeometryResult
}

enum GeometryAlgorithm: String, Equatable, Sendable { case openEllipticalLoftV1 = "open-elliptical-loft-v1" }
enum GeometryProvenance: String, Equatable, Sendable { case reviewedSyntheticFixture = "reviewed-synthetic-fixture" }
enum GeometryInterpolation: String, Equatable, Sendable { case betweenObservedSectionsOnly = "between-observed-sections-only" }
enum GeometryUnknownRegionPolicy: String, Equatable, Sendable { case unmodeledAndUnbridged = "unmodeled-and-unbridged" }
enum GeometryValidationStatus: String, Equatable, Sendable { case validated = "validated" }
enum GeometryRendererCapability: String, Equatable, Sendable { case neutralIllustrationOnly = "neutral-illustration-only" }


/// Serial CPU generator. The only successful inputs come from the sealed fixture factory.
actor SyntheticGeometryGenerator: GeometryGenerating {
    init() {}

    func generate(_ fixture: GeometryFixtureID) async throws -> GeometryResult {
        guard !Task.isCancelled else { throw GeometryFailure.cancelled }
        let input = try GeometryKernel.reviewedFixture(fixture)
        let result = try GeometryKernel.generate(input, cancellationCheck: { Task.isCancelled })
        guard !Task.isCancelled else { throw GeometryFailure.cancelled }
        return result
    }
}
#endif
