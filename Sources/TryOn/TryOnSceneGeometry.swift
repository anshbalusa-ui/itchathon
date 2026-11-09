@preconcurrency import SceneKit
import UIKit
import simd


final class TryOnPreparedGarment: @unchecked Sendable {
  private let geometry: SCNGeometry

  init(mesh: TryOnMesh, front: CGImage, backColor: SIMD3<Float>) throws {
    guard mesh.positions.count >= 100, mesh.positions.count <= 250_000,
          mesh.positions.count == mesh.textureCoordinates.count,
          mesh.positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
          mesh.textureCoordinates.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
          !mesh.front.isEmpty, !mesh.back.isEmpty, mesh.front.count % 3 == 0, mesh.back.count % 3 == 0,
          mesh.front.allSatisfy({ Int($0) < mesh.positions.count }), mesh.back.allSatisfy({ Int($0) < mesh.positions.count }) else { throw TryOnError.geometry }
    var normals = [SIMD3<Float>](repeating: .zero, count: mesh.positions.count)
    func accumulate(_ indices: [UInt32]) throws {
      for face in stride(from: 0, to: indices.count, by: 3) {
        let a = Int(indices[face]), b = Int(indices[face + 1]), c = Int(indices[face + 2])
        let normal = simd_cross(mesh.positions[b] - mesh.positions[a], mesh.positions[c] - mesh.positions[a])
        guard simd_length_squared(normal) > 1e-14 else { throw TryOnError.geometry }
        normals[a] += normal; normals[b] += normal; normals[c] += normal
      }
    }
    try accumulate(mesh.front); try accumulate(mesh.back)
    let sources: [SCNGeometrySource] = [
      .init(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }),
      .init(normals: normals.map { value in
        let normal = simd_length_squared(value) > 1e-14 ? simd_normalize(value) : SIMD3<Float>(0, 0, 1)
        return SCNVector3(normal.x, normal.y, normal.z)
      }),
      .init(textureCoordinates: mesh.textureCoordinates.map { CGPoint(x: Double($0.x), y: Double($0.y)) })
    ]
    // UInt32 indices remove the old silent UInt16/65,535-vertex omission path.
    geometry = SCNGeometry(sources: sources, elements: [
      SCNGeometryElement(indices: mesh.front, primitiveType: .triangles),
      SCNGeometryElement(indices: mesh.back, primitiveType: .triangles)
    ])
    let frontMaterial = SCNMaterial()
    frontMaterial.lightingModel = .physicallyBased
    frontMaterial.diffuse.contents = UIImage(cgImage: front)
    frontMaterial.roughness.contents = 0.82
    frontMaterial.metalness.contents = 0
    frontMaterial.isDoubleSided = false
    let backMaterial = SCNMaterial()
    backMaterial.lightingModel = .physicallyBased
    backMaterial.diffuse.contents = UIColor(red: CGFloat(backColor.x), green: CGFloat(backColor.y), blue: CGFloat(backColor.z), alpha: 1)
    backMaterial.roughness.contents = 0.86
    backMaterial.metalness.contents = 0
    backMaterial.isDoubleSided = false
    geometry.materials = [frontMaterial, backMaterial]
  }

  func makeNode() -> SCNNode {
    let node = SCNNode(geometry: geometry)
    node.name = "tryon.garment"
    return node
  }
}
