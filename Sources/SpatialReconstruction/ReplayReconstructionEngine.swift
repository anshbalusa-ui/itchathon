#if DEBUG
import Foundation

enum ReplayResultCapability: String, Equatable, Sendable { case neutralSyntheticIllustrationV1 = "neutral-synthetic-illustration-v1" }
enum ReplayResultProvenance: String, Equatable, Sendable { case reviewedFirstPartyDepthReplay = "reviewed-first-party-depth-replay" }
enum ReplayUnknownRegionPolicy: String, Equatable, Sendable { case unmodeledAndUnbridged = "unmodeled-and-unbridged" }
private enum ReplayResultSeal: Equatable, Sendable { case reconstructedDepthReplayV1 }

/// Immutable result minted solely after successful replay admission, observation fitting and mesh validation.
struct ReplayGeometryResult: Equatable, Sendable {
    let id: ReplayID
    let mesh: GeometryMesh
    let sections: [ReplaySection]
    let mappingSummaries: [ReplayMappingSummary]
    let supportedAngularIndices: [Int]
    let stages: [ReplayStage]
    let schemaVersion: Int
    let capability: ReplayResultCapability
    let provenance: ReplayResultProvenance
    let unknownRegionPolicy: ReplayUnknownRegionPolicy
    private let seal: ReplayResultSeal

    fileprivate init(id: ReplayID, mesh: GeometryMesh, sections: [ReplaySection],
                     mappingSummaries: [ReplayMappingSummary], stages: [ReplayStage],
                     supportedAngularIndices: [Int]) {
        self.id = id
        self.mesh = mesh
        self.sections = sections
        self.mappingSummaries = mappingSummaries
        self.supportedAngularIndices = supportedAngularIndices
        self.stages = stages
        self.schemaVersion = 1
        self.capability = .neutralSyntheticIllustrationV1
        self.provenance = .reviewedFirstPartyDepthReplay
        self.unknownRegionPolicy = .unmodeledAndUnbridged
        self.seal = .reconstructedDepthReplayV1
    }

    func validate() throws {
        guard seal == .reconstructedDepthReplayV1, schemaVersion == 1,
              capability == .neutralSyntheticIllustrationV1, provenance == .reviewedFirstPartyDepthReplay,
              unknownRegionPolicy == .unmodeledAndUnbridged,
              stages == [.framesValidated, .pointsMapped, .viewsRegistered, .sectionsExtracted, .meshGenerated],
              sections.count == ReplayLimits.sectionHeights.count, mappingSummaries.count == 2 else { throw ReplayFailure.invalidMesh }
        for (section, expectedHeight) in zip(sections, ReplayLimits.sectionHeights) {
            guard section.height == expectedHeight, section.halfWidth.isFinite, section.halfDepth.isFinite,
                  section.maximumResidual.isFinite, section.halfWidth >= 0.01, section.halfDepth >= 0.01,
                  section.halfWidth <= 0.4, section.halfDepth <= 0.4,
                  section.frontSamples >= ReplayLimits.minimumPointsPerSectionView,
                  section.sideSamples >= ReplayLimits.minimumPointsPerSectionView,
                  section.maximumResidual <= ReplayLimits.maximumImplicitResidual else { throw ReplayFailure.invalidMesh }
        }
        let fullSupportMask = (UInt32(1) << UInt32(ReplayLimits.radialSegments)) - 1
        guard supportedAngularIndices.count >= ReplayLimits.minimumSupportedAngularVertices,
              supportedAngularIndices.count <= ReplayLimits.radialSegments,
              supportedAngularIndices.allSatisfy({ (0..<ReplayLimits.radialSegments).contains($0) }),
              sections.allSatisfy({ $0.angularSupportMask & ~fullSupportMask == 0 }),
              sections.allSatisfy({ section in
                  supportedAngularIndices.allSatisfy { section.angularSupportMask & (UInt32(1) << UInt32($0)) != 0 }
              }) else { throw ReplayFailure.invalidMesh }
        for index in 1..<supportedAngularIndices.count {
            guard (supportedAngularIndices[index] - supportedAngularIndices[index - 1] + ReplayLimits.radialSegments)
                    % ReplayLimits.radialSegments == 1 else { throw ReplayFailure.invalidMesh }
        }
        let closesRing = supportedAngularIndices.count == ReplayLimits.radialSegments
        let expectedVertices = sections.count * supportedAngularIndices.count
        let expectedIndices = (sections.count - 1) *
            (supportedAngularIndices.count - (closesRing ? 0 : 1)) * 6
        guard mesh.vertices.count == expectedVertices, mesh.indices.count == expectedIndices else {
            throw ReplayFailure.invalidMesh
        }
        let hasFront = mappingSummaries[0].view == .front
        let hasSide = mappingSummaries[1].view == .side
        guard hasFront, hasSide,
              mappingSummaries.allSatisfy({ !$0.frameID.isEmpty && !$0.captureID.isEmpty && $0.counts.accepted > 0 &&
                  finite($0.minimum) && finite($0.maximum) && $0.minimum.x <= $0.maximum.x &&
                  $0.minimum.y <= $0.maximum.y && $0.minimum.z <= $0.maximum.z }) else { throw ReplayFailure.invalidMesh }
        do { try mesh.validate() } catch { throw ReplayFailure.invalidMesh }
    }

    private func finite(_ p: SIMD3<Double>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
}

enum ReplayReconstructionEngine {
    static func reconstruct(_ replay: ReviewedSyntheticReplay,
                            cancellationCheck: () -> Bool = { Task.isCancelled }) throws -> ReplayGeometryResult {
        try check(cancellationCheck)
        guard replay.schemaVersion == ReplayLimits.schemaVersion, replay.capability == .firstPartyRayCastV1 else {
            throw ReplayFailure.unsupportedVersion
        }
        let analysis = try ReplaySpatialMapper.analyze(frames: replay.frames, evaluationTimestamp: replay.evaluationTimestamp,
                                                       cancellationCheck: cancellationCheck)
        try check(cancellationCheck)
        let supportedAngularIndices = try commonAngularRun(analysis.sections)
        let numericSections = analysis.sections.map { section in
            GeometrySectionInput(heightMetres: Float(section.height), halfWidthMetres: Float(section.halfWidth),
                                 halfDepthMetres: Float(section.halfDepth))
        }
        let mesh: GeometryMesh
        do {
            mesh = try GeometrySectionLoft.generate(sections: numericSections, radialSegments: ReplayLimits.radialSegments,
                                                    angularIndices: supportedAngularIndices,
                                                    cancellationCheck: cancellationCheck)
        } catch GeometryFailure.cancelled {
            throw ReplayFailure.cancelled
        }
        catch {
            throw ReplayFailure.invalidMesh
        }
        try check(cancellationCheck)
        let summaries = analysis.views.map { view -> ReplayMappingSummary in
            var minimum = SIMD3<Double>(repeating: .infinity), maximum = SIMD3<Double>(repeating: -.infinity)
            for point in view.points {
                minimum = SIMD3(min(minimum.x, point.x), min(minimum.y, point.y), min(minimum.z, point.z))
                maximum = SIMD3(max(maximum.x, point.x), max(maximum.y, point.y), max(maximum.z, point.z))
            }
            return ReplayMappingSummary(view: view.view, frameID: view.frameID, captureID: view.captureID,
                referenceFrame: view.referenceFrame, counts: view.counts, minimum: minimum, maximum: maximum)
        }
        let result = ReplayGeometryResult(id: replay.id, mesh: mesh, sections: analysis.sections,
            mappingSummaries: summaries,
            stages: [.framesValidated, .pointsMapped, .viewsRegistered, .sectionsExtracted, .meshGenerated],
            supportedAngularIndices: supportedAngularIndices)
        try result.validate()
        try check(cancellationCheck)
        return result
    }
    /// Only the longest common contiguous arc observed at every selected height is lofted;
    /// unsupported angular gaps never receive vertices, faces or a fabricated closure.
    private static func commonAngularRun(_ sections: [ReplaySection]) throws -> [Int] {
        guard sections.count == ReplayLimits.sectionHeights.count else { throw ReplayFailure.insufficientCoverage }
        let fullMask = (UInt32(1) << UInt32(ReplayLimits.radialSegments)) - 1
        let common = sections.reduce(fullMask) { $0 & $1.angularSupportMask } & fullMask
        guard common != 0 else { throw ReplayFailure.insufficientCoverage }
        if common == fullMask { return Array(0..<ReplayLimits.radialSegments) }
        var bestStart = 0, bestLength = 0
        for start in 0..<ReplayLimits.radialSegments {
            let bit = UInt32(1) << UInt32(start)
            let previous = (start + ReplayLimits.radialSegments - 1) % ReplayLimits.radialSegments
            guard common & bit != 0, common & (UInt32(1) << UInt32(previous)) == 0 else { continue }
            var length = 1
            while length < ReplayLimits.radialSegments {
                let next = (start + length) % ReplayLimits.radialSegments
                guard common & (UInt32(1) << UInt32(next)) != 0 else { break }
                length += 1
            }
            if length > bestLength {
                bestStart = start
                bestLength = length
            }
        }
        guard bestLength >= ReplayLimits.minimumSupportedAngularVertices else { throw ReplayFailure.insufficientCoverage }
        return (0..<bestLength).map { (bestStart + $0) % ReplayLimits.radialSegments }
    }
    private static func check(_ check: () -> Bool) throws { if check() { throw ReplayFailure.cancelled } }
}
/// Actor-isolated CPU orchestration keeps synthetic raster generation and fitting off UI actors.
actor SyntheticReplayReconstructor: ReplayReconstructing {
    func reconstruct(_ replayID: ReplayID) async throws -> ReplayGeometryResult {
        let replay = try SyntheticDepthReplayFactory.make(replayID)
        return try ReplayReconstructionEngine.reconstruct(replay)
    }
}
#endif
