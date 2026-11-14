import Foundation
import simd

struct BodyModelGeometry: Sendable {
  let body: RendererMesh
  let shorts: RendererMesh
}

actor BodyModelGenerator {
  static let shared = BodyModelGenerator()

  private struct Prepared: Sendable {
    let reference: RendererMesh
    let shorts: RendererMesh
    let kernel: BodyShapeKernel
  }
  private var prepared: Prepared?

  func generate(_ measurements: BodyMeasurements) throws -> BodyModelGeometry {
    try Task.checkCancellation()
    guard measurements.isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
    if prepared == nil {
      prepared = try Self.prepare(HumanShowcaseAssets.load())
    }
    guard let prepared else { throw HumanShowcaseAssetFailure.rejectedPayload }
    try Task.checkCancellation()
    let body = try prepared.kernel.shape(prepared.reference, to: measurements)
    try Task.checkCancellation()
    let shorts = try prepared.kernel.shape(prepared.shorts, to: measurements)
    return BodyModelGeometry(body: body, shorts: shorts)
  }

  private static func prepare(_ source: HumanShowcaseMeshes) throws -> Prepared {
    var points = source.body.vertices.map(\.position)
    var indices = source.body.indices
    try SmoothMeshGeometry.subdivide(points: &points, indices: &indices)
    let bounds = points.reduce(into: (min: Float.greatestFiniteMagnitude, max: -Float.greatestFiniteMagnitude)) {
      $0.min = min($0.min, $1.y); $0.max = max($0.max, $1.y)
    }
    let minimumY = bounds.min, maximumY = bounds.max
    guard maximumY > minimumY else {
      throw HumanShowcaseAssetFailure.rejectedPayload
    }
    let scale = 1.8 / (maximumY - minimumY)
    for index in points.indices {
      if index.isMultiple(of: 1024), Task.isCancelled { throw CancellationError() }
      points[index].y = (points[index].y - minimumY) * scale
    }
    let reference = mesh(points: points, indices: indices)
    let kernel = try BodyShapeKernel(reference: reference)
    var shortsPoints = source.shorts.vertices.map(\.position)
    for index in shortsPoints.indices {
      if index.isMultiple(of: 1024), Task.isCancelled { throw CancellationError() }
      shortsPoints[index].y = (shortsPoints[index].y - minimumY) * scale
    }
    let pelvis = pelvisShorts(from: mesh(points: shortsPoints, indices: source.shorts.indices))
    shortsPoints = pelvis.vertices.map(\.position)
    var shortsIndices = pelvis.indices
    try SmoothMeshGeometry.subdivide(points: &shortsPoints, indices: &shortsIndices, allowBoundary: true)
    return Prepared(reference: reference, shorts: mesh(points: shortsPoints, indices: shortsIndices), kernel: kernel)
  }

  /// The illustration payload can contain disconnected clipped hand remnants;
  /// retain the component that contains the central pelvis garment.
  private static func pelvisShorts(from source: RendererMesh) -> RendererMesh {
    let triangleCount = source.indices.count / 3
    guard triangleCount > 0 else { return source }
    var vertexFaces = Array(repeating: [Int](), count: source.vertices.count)
    for face in 0..<triangleCount {
      for corner in 0..<3 { vertexFaces[Int(source.indices[face * 3 + corner])].append(face) }
    }
    var visited = Array(repeating: false, count: triangleCount)
    var best: [Int] = []
    var bestScore = -1
    for seed in 0..<triangleCount where !visited[seed] {
      var component: [Int] = []
      var pending = [seed]
      visited[seed] = true
      var pelvisScore = 0
      while let face = pending.popLast() {
        component.append(face)
        let a = source.vertices[Int(source.indices[face * 3])].position
        let b = source.vertices[Int(source.indices[face * 3 + 1])].position
        let c = source.vertices[Int(source.indices[face * 3 + 2])].position
        let center = (a + b + c) / 3
        if (0.32...0.78).contains(center.y) && abs(center.x) < 0.22 { pelvisScore += 1 }
        for corner in 0..<3 {
          let vertex = Int(source.indices[face * 3 + corner])
          for neighbor in vertexFaces[vertex] where !visited[neighbor] {
            visited[neighbor] = true
            pending.append(neighbor)
          }
        }
      }
      if pelvisScore > bestScore { best = component; bestScore = pelvisScore }
    }
    guard !best.isEmpty, bestScore > 0, best.count < triangleCount else { return source }
    var sourceToCompact = Array(repeating: -1, count: source.vertices.count)
    var compactPoints: [SIMD3<Float>] = []
    compactPoints.reserveCapacity(best.count)
    var indices: [UInt16] = []
    indices.reserveCapacity(best.count * 3)
    for face in best {
      for corner in 0..<3 {
        let sourceIndex = Int(source.indices[face * 3 + corner])
        if sourceToCompact[sourceIndex] < 0 {
          sourceToCompact[sourceIndex] = compactPoints.count
          compactPoints.append(source.vertices[sourceIndex].position)
        }
        indices.append(UInt16(sourceToCompact[sourceIndex]))
      }
    }
    return mesh(points: compactPoints, indices: indices)
  }

  private static func mesh(points: [SIMD3<Float>], indices: [UInt16]) -> RendererMesh {
    var vertices = Array(repeating: SIMD3<Float>.zero, count: points.count)
    for offset in stride(from: 0, to: indices.count, by: 3) {
      let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
      let normal = simd_cross(points[b] - points[a], points[c] - points[a])
      vertices[a] += normal; vertices[b] += normal; vertices[c] += normal
    }
    var result: [RendererVertex] = []
    result.reserveCapacity(points.count)
    for index in points.indices {
      let normal = vertices[index]
      result.append(RendererVertex(position: points[index], normal: simd_length_squared(normal) > 1e-14 ? simd_normalize(normal) : SIMD3(0, 1, 0)))
    }
    let bounds = points.reduce(into: (minimum: SIMD3<Float>(repeating: .greatestFiniteMagnitude), maximum: SIMD3<Float>(repeating: -.greatestFiniteMagnitude))) {
      $0.minimum = simd_min($0.minimum, $1); $0.maximum = simd_max($0.maximum, $1)
    }
    return RendererMesh(vertices: result, indices: indices, minimum: bounds.minimum, maximum: bounds.maximum)
  }
}
