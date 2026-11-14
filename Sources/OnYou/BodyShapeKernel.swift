import Foundation
import simd

struct BodyShapeKernel: Sendable {
  private var chest: Float
  private var waist: Float
  private var hips: Float
  private var shoulderWidth: Float
  private let chestRadius: Float
  private let waistRadius: Float

  init(reference: RendererMesh) throws {
    let points = reference.vertices.map(\.position)
    let chestSection = try SmoothMeshGeometry.centralSection(points: points, indices: reference.indices, y: 1.30)
    let waistSection = try SmoothMeshGeometry.centralSection(points: points, indices: reference.indices, y: 1.08)
    chest = chestSection.perimeter
    waist = waistSection.perimeter
    chestRadius = chestSection.width * 0.5
    waistRadius = waistSection.width * 0.5
    hips = try SmoothMeshGeometry.centralSection(points: points, indices: reference.indices, y: 0.91).perimeter
    shoulderWidth = try SmoothMeshGeometry.centralSection(points: points, indices: reference.indices, y: 1.44).width
    guard [chest, waist, hips, shoulderWidth].allSatisfy({ $0.isFinite && $0 > 0.3 }) else {
      throw CocoaError(.coderReadCorrupt)
    }
  }

  func shape(_ mesh: RendererMesh, to measurements: BodyMeasurements) throws -> RendererMesh {
    guard measurements.isValid else { throw CocoaError(.validationMissingMandatoryProperty) }
    let heightScale = Float(measurements.height / 180)
    let targetShoulderWidth = Float(measurements.shoulders / 100)
    let shoulderScale = targetShoulderWidth / shoulderWidth
    let shoulderTranslation = (targetShoulderWidth - shoulderWidth * heightScale) * 0.5
    let chestScale = Float(measurements.chest / 100) / chest
    let waistScale = Float(measurements.waist / 100) / waist
    // Give a broader torso clearance by moving the limb, not squeezing its
    // cross-section into the torso-to-arm transition. Unmeasured arm girth
    // stays at the height-scaled anatomical reference.
    let lowerArmTranslation = max(shoulderTranslation,
      max(chestRadius * (chestScale - heightScale), waistRadius * (waistScale - heightScale)))
    let anchors: [(Float, Float)] = [
      (0, heightScale), (0.6, heightScale),
      (0.91, Float(measurements.hips / 100) / hips),
      (1.08, waistScale),
      (1.30, chestScale),
      (1.44, shoulderScale),
      (1.57, heightScale), (1.81, heightScale)
    ]
    var vertices: [RendererVertex] = []
    vertices.reserveCapacity(mesh.vertices.count)
    for (index, vertex) in mesh.vertices.enumerated() {
      if index.isMultiple(of: 1024) { try Task.checkCancellation() }
      let p = vertex.position
      var upper = 1
      while upper < anchors.count && p.y > anchors[upper].0 { upper += 1 }
      upper = min(upper, anchors.count - 1)
      let lower = upper - 1
      let t = min(1, max(0, (p.y - anchors[lower].0) / (anchors[upper].0 - anchors[lower].0)))
      let blend = t * t * (3 - 2 * t)
      let scale = anchors[lower].1 + (anchors[upper].1 - anchors[lower].1) * blend

      // Keep the transition in the A-pose's torso/arm gap. Near the deltoid
      // it blends back to the measured shoulder span; below it the limb moves
      // rigidly, preserving the upper arm, elbow, forearm and finger detail.
      let start = 0.17 + max(0, 1.30 - p.y) * 0.45
      let shoulderT = min(1, max(0, (p.y - 1.34) / 0.10))
      let shoulderBlend = shoulderT * shoulderT * (3 - 2 * shoulderT)
      let headT = min(1, max(0, (p.y - 1.50) / 0.10))
      let shift = (lowerArmTranslation * (1 - shoulderBlend) + shoulderTranslation * shoulderBlend)
        * (1 - headT * headT * (3 - 2 * headT))
      let end = max(start + 0.06, (start * scale - shift) / heightScale + 0.015)
      let radius = abs(p.x)
      let xRadius = Self.mapRadius(radius, scale: scale, heightScale: heightScale, start: start, end: end, shift: shift)
      let armT = min(1, max(0, (radius - start) / (end - start)))
      let armBlend = armT * armT * (3 - 2 * armT)
      let depthScale = scale * (1 - armBlend) + heightScale * armBlend
      let centerZ: Float = 0.055
      let position = SIMD3(p.x < 0 ? -xRadius : xRadius, p.y * heightScale, centerZ + (p.z - centerZ) * depthScale)
      vertices.append(RendererVertex(position: position, normal: .zero))
    }
    for face in stride(from: 0, to: mesh.indices.count, by: 3) {
      if face.isMultiple(of: 3072) { try Task.checkCancellation() }
      let a = Int(mesh.indices[face]), b = Int(mesh.indices[face + 1]), c = Int(mesh.indices[face + 2])
      let normal = simd_cross(vertices[b].position - vertices[a].position, vertices[c].position - vertices[a].position)
      vertices[a].normal += normal
      vertices[b].normal += normal
      vertices[c].normal += normal
    }
    for i in vertices.indices {
      if i.isMultiple(of: 1024) { try Task.checkCancellation() }
      let normal = vertices[i].normal
      vertices[i].normal = simd_length_squared(normal) > 1e-14 ? simd_normalize(normal) : mesh.vertices[i].normal
    }
    let minimum = vertices.reduce(SIMD3<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1.position) }
    let maximum = vertices.reduce(SIMD3<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1.position) }
    return RendererMesh(vertices: vertices, indices: mesh.indices, minimum: minimum, maximum: maximum)
  }

  private static func mapRadius(_ radius: Float, scale: Float, heightScale: Float, start: Float, end: Float, shift: Float) -> Float {
    if radius <= start { return radius * scale }
    if radius >= end { return radius * heightScale + shift }
    let width = end - start
    let lower = start * scale
    let upper = end * heightScale + shift
    let secant = (upper - lower) / width
    var lowerSlope = scale
    var upperSlope = heightScale
    let magnitude = (lowerSlope / secant) * (lowerSlope / secant) + (upperSlope / secant) * (upperSlope / secant)
    if magnitude > 9 {
      let limit = 3 / sqrt(magnitude)
      lowerSlope *= limit
      upperSlope *= limit
    }
    let t = (radius - start) / width
    let t2 = t * t
    let t3 = t2 * t
    return (2 * t3 - 3 * t2 + 1) * lower
      + (t3 - 2 * t2 + t) * width * lowerSlope
      + (-2 * t3 + 3 * t2) * upper
      + (t3 - t2) * width * upperSlope
  }

  /// Measures the centerline-connected trunk section, excluding disconnected arm loops.
  static func circumference(_ mesh: RendererMesh, at height: Float) -> Float {
    (try? SmoothMeshGeometry.centralSection(
      points: mesh.vertices.map(\.position), indices: mesh.indices, y: height
    ).perimeter) ?? 0
  }
}
