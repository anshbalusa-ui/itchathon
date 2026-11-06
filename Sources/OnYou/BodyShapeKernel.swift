import Foundation
import simd

struct BodyShapeKernel {
  private var chest: Float
  private var waist: Float
  private var hips: Float

  init(reference: RendererMesh) throws {
    chest = Self.circumference(reference, at: 1.30)
    waist = Self.circumference(reference, at: 1.08)
    hips = Self.circumference(reference, at: 0.91)
    guard [chest, waist, hips].allSatisfy({ $0.isFinite && $0 > 0.3 }) else {
      throw CocoaError(.coderReadCorrupt)
    }
  }

  func shape(_ mesh: RendererMesh, to measurements: BodyMeasurements) throws -> RendererMesh {
    guard measurements.isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
    let heightScale = Float(measurements.height / 180)
    let anchors: [(Float, Float)] = [
      (0, heightScale), (0.6, heightScale),
      (0.91, Float(measurements.hips / 100) / hips),
      (1.08, Float(measurements.waist / 100) / waist),
      (1.30, Float(measurements.chest / 100) / chest),
      (1.44, Float(measurements.shoulders / 42)),
      (1.57, heightScale), (1.81, heightScale)
    ]
    var vertices = mesh.vertices.map { vertex -> RendererVertex in
      let p = vertex.position
      let interval = zip(anchors, anchors.dropFirst()).first { p.y <= $0.1.0 } ?? (anchors[6], anchors[7])
      let t = min(1, max(0, (p.y - interval.0.0) / (interval.1.0 - interval.0.0)))
      let blend = t * t * (3 - 2 * t)
      let scale = interval.0.1 + (interval.1.1 - interval.0.1) * blend
      // Keep hands and forearms proportional while moving them with the torso.
      let armWeight = p.y > 0.95 && p.y < 1.5 ? min(1, max(0, (abs(p.x) - 0.20) / 0.08)) : 0
      let x = p.x * scale * (1 - armWeight)
        + (p.x.sign == .minus ? -1 : 1) * (0.20 * scale + (abs(p.x) - 0.20) * heightScale) * armWeight
      let depthScale = scale * (1 - armWeight) + heightScale * armWeight
      let centerZ: Float = 0.055
      return RendererVertex(position: SIMD3(x, p.y * heightScale, centerZ + (p.z - centerZ) * depthScale), normal: .zero)
    }
    for face in stride(from: 0, to: mesh.indices.count, by: 3) {
      let a = Int(mesh.indices[face]), b = Int(mesh.indices[face + 1]), c = Int(mesh.indices[face + 2])
      let normal = simd_cross(vertices[b].position - vertices[a].position, vertices[c].position - vertices[a].position)
      vertices[a].normal += normal
      vertices[b].normal += normal
      vertices[c].normal += normal
    }
    for i in vertices.indices {
      let n = vertices[i].normal
      vertices[i].normal = simd_length_squared(n) > 1e-14 ? simd_normalize(n) : mesh.vertices[i].normal
    }
    let minimum = vertices.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1.position) }
    let maximum = vertices.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1.position) }
    return RendererMesh(vertices: vertices, indices: mesh.indices, minimum: minimum, maximum: maximum)
  }

  /// Convex torso section perimeter; arm intersections are outside the admitted torso window.
  static func circumference(_ mesh: RendererMesh, at height: Float) -> Float {
    var points: [SIMD2<Float>] = []
    for i in stride(from: 0, to: mesh.indices.count, by: 3) {
      let triangle = (0..<3).map { mesh.vertices[Int(mesh.indices[i + $0])].position }
      for edge in 0..<3 {
        let a = triangle[edge], b = triangle[(edge + 1) % 3]
        guard (a.y <= height && b.y > height) || (b.y <= height && a.y > height) else { continue }
        let p = a + (b - a) * ((height - a.y) / (b.y - a.y))
        if abs(p.x) < 0.225 { points.append(SIMD2(p.x, p.z)) }
      }
    }
    points.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    guard points.count >= 3 else { return 0 }
    func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    func half(_ values: [SIMD2<Float>]) -> [SIMD2<Float>] {
      var result: [SIMD2<Float>] = []
      for p in values {
        while result.count >= 2 && cross(result[result.count - 2], result[result.count - 1], p) <= 0 {
          result.removeLast()
        }
        result.append(p)
      }
      return result
    }
    let hull = Array(half(points).dropLast()) + Array(half(points.reversed()).dropLast())
    guard hull.count >= 3 else { return 0 }
    return hull.indices.reduce(0) { $0 + simd_distance(hull[$1], hull[($1 + 1) % hull.count]) }
  }
}
