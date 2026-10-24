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

        let vertexBytes = result.mesh.vertices.count.multipliedReportingOverflow(by: MemoryLayout<RendererVertex>.stride)
        let indexBytes = result.mesh.indices.count.multipliedReportingOverflow(by: MemoryLayout<UInt16>.stride)
        guard !vertexBytes.overflow, !indexBytes.overflow,
              vertexBytes.partialValue <= GeometryMesh.maximumPayloadBytes,
              indexBytes.partialValue <= GeometryMesh.maximumPayloadBytes - vertexBytes.partialValue else {
            throw GeometryFailure.invalidMesh
        }

        let vertices = result.mesh.vertices.map {
            RendererVertex(position: $0.position, normal: $0.normal)
        }
        return RendererMesh(vertices: vertices, indices: result.mesh.indices,
                            minimum: result.mesh.minimum, maximum: result.mesh.maximum)
    }
}
#endif
