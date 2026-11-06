#if DEBUG
import XCTest
@testable import FitCheck

final class GeometryReconstructionTests: XCTestCase {
    private func generate(_ fixture: GeometryFixtureID) async throws -> GeometryResult {
        try await SyntheticGeometryGenerator().generate(fixture)
    }

    private func sections(_ heights: [Float] = [0.4, 0.55, 0.70, 0.85]) -> [GeometrySectionInput] {
        heights.map { GeometrySectionInput(heightMetres: $0, halfWidthMetres: 0.15, halfDepthMetres: 0.10) }
    }

    private func input(
        _ sections: [GeometrySectionInput] = [
            GeometrySectionInput(heightMetres: 0.4, halfWidthMetres: 0.15, halfDepthMetres: 0.1),
            GeometrySectionInput(heightMetres: 0.55, halfWidthMetres: 0.16, halfDepthMetres: 0.11),
            GeometrySectionInput(heightMetres: 0.7, halfWidthMetres: 0.17, halfDepthMetres: 0.12),
            GeometrySectionInput(heightMetres: 0.85, halfWidthMetres: 0.16, halfDepthMetres: 0.11)
        ], schema: Int = 1, source: GeometryInputSource = .reviewedSynthetic,
        units: GeometryInputUnits = .metres,
        orientation: GeometryInputOrientation = .rightHandedYUpZFrontFloorCentred,
        unknown: [ClosedRange<Float>] = [], radial: Int = 24, scale: Float = 1,
        capability: GeometryInputCapability = .openSectionLoftV1
    ) -> GeometryInput {
        GeometryInput(schemaVersion: schema, source: source, units: units, orientation: orientation,
                      sections: sections, unknownRegionsMetres: unknown, radialSegments: radial,
                      metresPerUnit: scale, capability: capability)
    }

    func testAuthorizedSyntheticFixturesExposeVersionedIllustrationMetadata() async throws {
        for fixture in [GeometryFixtureID.surfaceA, .surfaceB] {
            let result = try await generate(fixture)
            XCTAssertNoThrow(try result.validate())
            XCTAssertEqual(result.fixture, fixture)
            XCTAssertEqual(result.schemaVersion, 1)
            XCTAssertEqual(result.algorithm, .openEllipticalLoftV1)
            XCTAssertEqual(result.provenance, .reviewedSyntheticFixture)
            XCTAssertEqual(result.interpolation, .betweenObservedSectionsOnly)
            XCTAssertEqual(result.unknownRegionPolicy, .unmodeledAndUnbridged)
            XCTAssertEqual(result.rendererCapability, .neutralIllustrationOnly)
            XCTAssertEqual(result.observedSectionHeightsMetres, [0.45, 0.62, 0.79, 0.96, 1.13, 1.30])
        }
    }

    func testAnalyticBoundsAndIndependentFrontSideProfiles() async throws {
        let a = try await generate(.surfaceA).mesh
        let b = try await generate(.surfaceB).mesh
        XCTAssertEqual(a.vertices.count, 6 * 24)
        XCTAssertEqual(a.indices.count, 5 * 2 * 24 * 3)
        XCTAssertEqual(a.minimum.y, 0.45, accuracy: 0.0001)
        XCTAssertEqual(a.maximum.y, 1.30, accuracy: 0.0001)
        XCTAssertEqual(a.maximum.x, 0.20, accuracy: 0.0001)
        XCTAssertEqual(a.minimum.x, -0.20, accuracy: 0.0001)
        XCTAssertEqual(a.maximum.z, 0.13, accuracy: 0.0001)
        XCTAssertEqual(a.minimum.z, -0.13, accuracy: 0.0001)
        XCTAssertEqual(b.maximum.x, 0.16, accuracy: 0.0001)
        XCTAssertEqual(b.maximum.z, 0.19, accuracy: 0.0001)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a.vertices.map(\.position), b.vertices.map(\.position))
    }

    func testMissingRegionIsRejectedWithoutFabricatedSurface() async {
        do { _ = try await generate(.missingRegion); XCTFail("A missing required region cannot produce a default surface") }
        catch { XCTAssertEqual(error as? GeometryFailure, .unavailableObservation) }
    }

    func testMalformedFixtureAndFutureOrUnverifiedInputsReject() async {
        do { _ = try await generate(.invalidGeometry); XCTFail("Expected invalid fixture rejection") }
        catch { XCTAssertEqual(error as? GeometryFailure, .nonFiniteValue) }
        do { _ = try await generate(.unverifiedSource); XCTFail("Expected unverified fixture rejection") }
        catch { XCTAssertEqual(error as? GeometryFailure, .unverifiedSource) }
        XCTAssertThrowsError(try GeometryKernel.generate(input(source: .scanner))) {
            XCTAssertEqual($0 as? GeometryFailure, .unverifiedSource)
        }
        XCTAssertThrowsError(try GeometryKernel.generate(input())) {
            XCTAssertEqual($0 as? GeometryFailure, .unverifiedSource)
        }
    }

    func testInputSchemaUnitsOrientationRolesAvailabilityAndQualityAreStrict() {
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(schema: 2))) {
            XCTAssertEqual($0 as? GeometryFailure, .unsupportedSchema)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(units: .centimetres))) {
            XCTAssertEqual($0 as? GeometryFailure, .unsupportedUnits)
        }
        for scale: Float in [.nan, .infinity, 0, 0.01] {
            XCTAssertThrowsError(try GeometryKernel.validate(input: input(scale: scale))) {
                XCTAssertEqual($0 as? GeometryFailure, .unsupportedUnits)
            }
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(capability: .unknown))) {
            XCTAssertEqual($0 as? GeometryFailure, .unsupportedSchema)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(orientation: .unknown))) {
            XCTAssertEqual($0 as? GeometryFailure, .unsupportedOrientation)
        }
        let badRole = sections().map { GeometrySectionInput(heightMetres: $0.heightMetres, halfWidthMetres: 0.15, halfDepthMetres: 0.1, role: .frontOnly) }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(badRole))) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidRole)
        }
        let unavailable = sections().map { GeometrySectionInput(heightMetres: $0.heightMetres, halfWidthMetres: 0.15, halfDepthMetres: 0.1, availability: .unavailable) }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(unavailable))) {
            XCTAssertEqual($0 as? GeometryFailure, .unavailableObservation)
        }
        let lowQuality = sections().map { GeometrySectionInput(heightMetres: $0.heightMetres, halfWidthMetres: 0.15, halfDepthMetres: 0.1, quality: .insufficient) }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(lowQuality))) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidQuality)
        }
    }

    func testNonfiniteDimensionsOrderingDuplicatesAndDiscontinuitiesReject() {
        var malformed = sections()
        malformed[1] = GeometrySectionInput(heightMetres: .nan, halfWidthMetres: 0.15, halfDepthMetres: 0.1)
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(malformed))) {
            XCTAssertEqual($0 as? GeometryFailure, .nonFiniteValue)
        }
        malformed = sections()
        malformed[1] = GeometrySectionInput(heightMetres: 0.55, halfWidthMetres: .infinity, halfDepthMetres: 0.1)
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(malformed))) {
            XCTAssertEqual($0 as? GeometryFailure, .nonFiniteValue)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(sections([0.4, 0.7, 0.55, 0.85])))) {
            XCTAssertEqual($0 as? GeometryFailure, .unorderedSections)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(sections([0.4, 0.55, 0.55, 0.85])))) {
            XCTAssertEqual($0 as? GeometryFailure, .duplicatedSection)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(sections([0.4, 0.55, 0.9, 1.05])))) {
            XCTAssertEqual($0 as? GeometryFailure, .discontinuousSections)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(sections([0.4, 0.55, 0.9, 1.05]), unknown: [0.55...0.9]))) {
            XCTAssertEqual($0 as? GeometryFailure, .unavailableObservation)
        }
    }

    func testDimensionSectionAndRadialLimitsPreflightBeforeAllocation() {
        XCTAssertThrowsError(try GeometryKernel.preflight(sectionCount: Int.max, radialSegments: 48)) {
            XCTAssertEqual($0 as? GeometryFailure, .resourceLimit)
        }
        XCTAssertThrowsError(try GeometryKernel.preflight(sectionCount: 32, radialSegments: Int.max)) {
            XCTAssertEqual($0 as? GeometryFailure, .resourceLimit)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(Array(repeating: sections()[0], count: 33)))) {
            XCTAssertEqual($0 as? GeometryFailure, .resourceLimit)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(radial: 49))) {
            XCTAssertEqual($0 as? GeometryFailure, .resourceLimit)
        }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(sections([0.4, 0.55, 0.70])))) {
            XCTAssertEqual($0 as? GeometryFailure, .insufficientSections)
        }
        let invalidSize = sections().map { GeometrySectionInput(heightMetres: $0.heightMetres, halfWidthMetres: 0.401, halfDepthMetres: 0.1) }
        XCTAssertThrowsError(try GeometryKernel.validate(input: input(invalidSize))) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidDimensions)
        }
        for extent: Float in [0, -0.1, .leastNonzeroMagnitude] {
            let invalid = sections().map { GeometrySectionInput(heightMetres: $0.heightMetres, halfWidthMetres: extent, halfDepthMetres: 0.1) }
            XCTAssertThrowsError(try GeometryKernel.validate(input: input(invalid))) {
                XCTAssertEqual($0 as? GeometryFailure, .invalidDimensions)
            }
        }
    }

    func testCancellationAndRepeatedGenerationAreDeterministic() async throws {
        XCTAssertThrowsError(try GeometryKernel.generate(
            GeometryKernel.reviewedFixture(.surfaceA), cancellationCheck: { true }
        )) { XCTAssertEqual($0 as? GeometryFailure, .cancelled) }
        let first = try await generate(.surfaceA)
        let second = try await generate(.surfaceA)
        XCTAssertEqual(first, second)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SyntheticGeometryGenerator().generate(.surfaceA)
        }
        do { _ = try await task.value; XCTFail("Expected cancelled generation") }
        catch { XCTAssertEqual(error as? GeometryFailure, .cancelled) }
    }

    func testMeshValidationRejectsNonfiniteIndicesDegeneracyWindingAndBounds() async throws {
        let valid = try await generate(.surfaceA).mesh
        XCTAssertNoThrow(try valid.validate())
        var vertices = valid.vertices
        vertices[0] = GeometryVertex(position: SIMD3<Float>(.nan, 0.45, 0), normal: vertices[0].normal)
        XCTAssertThrowsError(try GeometryMesh(vertices: vertices, indices: valid.indices, minimum: valid.minimum, maximum: valid.maximum).validate()) {
            XCTAssertEqual($0 as? GeometryFailure, .nonFiniteValue)
        }
        for normal in [SIMD3<Float>.zero, SIMD3<Float>(.infinity, 0, 0)] {
            vertices = valid.vertices
            vertices[0] = GeometryVertex(position: vertices[0].position, normal: normal)
            XCTAssertThrowsError(try GeometryMesh(vertices: vertices, indices: valid.indices, minimum: valid.minimum, maximum: valid.maximum).validate())
        }
        var indices = valid.indices
        indices[0] = UInt16.max
        XCTAssertThrowsError(try GeometryMesh(vertices: valid.vertices, indices: indices, minimum: valid.minimum, maximum: valid.maximum).validate()) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidMesh)
        }
        indices = valid.indices
        indices[0] = indices[1]
        XCTAssertThrowsError(try GeometryMesh(vertices: valid.vertices, indices: indices, minimum: valid.minimum, maximum: valid.maximum).validate()) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidMesh)
        }
        indices = valid.indices
        indices.swapAt(1, 2)
        XCTAssertThrowsError(try GeometryMesh(vertices: valid.vertices, indices: indices, minimum: valid.minimum, maximum: valid.maximum).validate()) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidMesh)
        }
        XCTAssertThrowsError(try GeometryMesh(vertices: valid.vertices, indices: valid.indices, minimum: SIMD3<Float>(0, 0, 0), maximum: valid.maximum).validate()) {
            XCTAssertEqual($0 as? GeometryFailure, .invalidMesh)
        }
        let huge = Array(repeating: valid.vertices[0], count: GeometryMesh.maximumVertices + 1)
        XCTAssertThrowsError(try GeometryMesh(vertices: huge, indices: valid.indices, minimum: valid.minimum, maximum: valid.maximum).validate())
    }
}
#endif
