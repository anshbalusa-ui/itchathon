#if DEBUG
import Foundation

/// Bridges only a validated, reviewed synthetic result into the existing Metal mesh format.
enum GeometryRendererAdapter {
    static func mesh(from result: GeometryResult) throws -> RendererMesh {
        try result.validate()
        guard result.provenance == .reviewedSyntheticFixture,
              result.rendererCapability == .neutralIllustrationOnly,
              result.mesh.vertices.count <= GeometryMesh.maximumVertices,
              result.mesh.indices.count <= GeometryMesh.maximumIndices else {
            throw GeometryFailure.invalidMetadata
        }
        return try rendererMesh(result.mesh)
    }

    static func mesh(from artifact: VerifiedSyntheticArtifact) throws -> RendererMesh {
        try artifact.validate()
        return try rendererMesh(artifact.mesh)
    }

    private static func rendererMesh(_ mesh: GeometryMesh) throws -> RendererMesh {
        let vertexBytes = mesh.vertices.count.multipliedReportingOverflow(by: MemoryLayout<RendererVertex>.stride)
        let indexBytes = mesh.indices.count.multipliedReportingOverflow(by: MemoryLayout<UInt16>.stride)
        guard !vertexBytes.overflow, !indexBytes.overflow,
              vertexBytes.partialValue <= GeometryMesh.maximumPayloadBytes,
              indexBytes.partialValue <= GeometryMesh.maximumPayloadBytes - vertexBytes.partialValue else {
            throw GeometryFailure.invalidMesh
        }

        let vertices = mesh.vertices.map {
            RendererVertex(position: $0.position, normal: $0.normal)
        }
        return RendererMesh(vertices: vertices, indices: mesh.indices,
                            minimum: mesh.minimum, maximum: mesh.maximum)
    }
}
#endif
