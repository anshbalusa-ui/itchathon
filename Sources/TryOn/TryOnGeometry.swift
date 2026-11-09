import Foundation
import simd

struct TryOnMesh: Sendable {
  var positions: [SIMD3<Float>]
  var textureCoordinates: [SIMD2<Float>]
  var front: [UInt32]
  var back: [UInt32]

  func removingDegenerateFaces() throws -> Self {
    func filtered(_ faces: [UInt32]) throws -> [UInt32] {
      guard faces.count % 3 == 0 else { throw TryOnError.geometry }
      var output: [UInt32] = []; output.reserveCapacity(faces.count)
      for i in stride(from: 0,to: faces.count,by: 3) {
        let a = Int(faces[i]), b = Int(faces[i+1]), c = Int(faces[i+2])
        guard positions.indices.contains(a),positions.indices.contains(b),positions.indices.contains(c) else { throw TryOnError.geometry }
        if simd_length_squared(simd_cross(positions[b]-positions[a],positions[c]-positions[a])) > 1e-14 {
          output.append(faces[i]); output.append(faces[i+1]); output.append(faces[i+2])
        }
      }
      return output
    }
    let f = try filtered(front), b = try filtered(back)
    guard !f.isEmpty,!b.isEmpty else { throw TryOnError.geometry }
    var used = Array(repeating: false,count: positions.count)
    for i in f { used[Int(i)] = true }; for i in b { used[Int(i)] = true }
    if !used.contains(false) { return Self(positions: positions,textureCoordinates: textureCoordinates,front: f,back: b) }
    var remap = Array(repeating: UInt32.max,count: positions.count), points: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
    for i in positions.indices where used[i] {
      remap[i] = UInt32(points.count); points.append(positions[i])
      if !textureCoordinates.isEmpty { uv.append(textureCoordinates[i]) }
    }
    return Self(positions: points,textureCoordinates: uv,front: f.map { remap[Int($0)] },back: b.map { remap[Int($0)] })
  }
}


struct TryOnSegment: Sendable {
  var a: SIMD2<Float>
  var b: SIMD2<Float>
  var minX: Float { min(a.x, b.x) }
  var maxX: Float { max(a.x, b.x) }
}

struct TryOnRing: Sendable {
  var points: [SIMD2<Float>]
  var requiredPerimeter: Float
  var tight: Bool
  private static let directions: [SIMD2<Float>] = (0..<64).map {
    let angle = Float($0) * 2 * .pi / 64
    return SIMD2(sin(angle),cos(angle))
  }

  static func make(segments: [TryOnSegment], centerX: Float, shoulderWidth: Float, circumference: Float) throws -> Self {
    guard circumference.isFinite, circumference > 0, centerX.isFinite, shoulderWidth > 0 else { throw TryOnError.geometry }
    var front = -Float.greatestFiniteMagnitude, back = Float.greatestFiniteMagnitude
    for segment in segments {
      let delta = segment.b.x - segment.a.x
      guard abs(delta) > 1e-8 else { continue }
      let t = (centerX - segment.a.x) / delta
      if (0...1).contains(t) {
        let z = segment.a.y + t * (segment.b.y - segment.a.y)
        front = max(front, z); back = min(back, z)
      }
    }
    guard front - back > 0.025 else { throw TryOnError.surface }
    let center = SIMD2(centerX, (front + back) / 2)
    let count = 64
    var radii: [Float?] = []
    radii.reserveCapacity(count)
    for i in 0..<count {
      let direction = directions[i]
      var nearest = Float.infinity
      for edge in segments {
        let vector = edge.b - edge.a, denominator = cross(direction, vector)
        guard abs(denominator) > 0.000001 else { continue }
        let t = cross(edge.a - center, vector) / denominator
        let u = cross(edge.a - center, direction) / denominator
        if t > 0.005 && (0...1).contains(u) { nearest = min(nearest, t) }
      }
      radii.append(nearest.isFinite ? nearest : nil)
    }
    guard radii.compactMap({ $0 }).count >= count - 4 else { throw TryOnError.surface }
    for i in 0..<count where radii[i] == nil {
      guard let left = (1...4).first(where: { radii[(i - $0 + count) % count] != nil }),
            let right = (1...4).first(where: { radii[(i + $0) % count] != nil }), left + right <= 5,
            let a = radii[(i - left + count) % count], let b = radii[(i + right) % count] else { throw TryOnError.surface }
      radii[i] = a + (b - a) * Float(left) / Float(left + right)
    }
    let observed = radii.compactMap { $0 }
    func ring(_ offset: Float) -> [SIMD2<Float>] {
      (0..<count).map { center + directions[$0] * (observed[$0] + offset) }
    }
    let required = perimeter(ring(0))
    // Bounded illustration: do not inflate a neck/chest into a 25 cm balloon
    // to pretend a very loose flat garment has a physically simulated volume.
    var offset = min(0.045, max(0.006, (circumference - required) / (2 * .pi)))
    for _ in 0..<2 {
      offset = min(0.045, max(0.006, offset + (circumference - perimeter(ring(offset))) / (2 * .pi)))
    }
    let points = ring(offset)
    return Self(points: points, requiredPerimeter: required, tight: circumference < required + 0.02)
  }


  private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
  private static func perimeter(_ points: [SIMD2<Float>]) -> Float {
    points.indices.reduce(0) { $0 + simd_distance(points[$1], points[($1 + 1) % points.count]) }
  }
}

struct TryOnBodyPose: Sendable {
  // Person's left is +X when facing +Z; photograph-left is -X.
  var neck: SIMD3<Float>
  var leftShoulder: SIMD3<Float>
  var rightShoulder: SIMD3<Float>
  var leftElbow: SIMD3<Float>
  var rightElbow: SIMD3<Float>
  var hips: SIMD3<Float>
}

struct TryOnPattern: Sendable {
  var width: Int
  var height: Int
  var alpha: [UInt8]
  var points: [SIMD2<Float>]
  var color: SIMD3<Float>


  func bodyEdges(at y: Float) -> (Float, Float) {
    let row = min(height - 1, max(0, Int(y * Float(height - 1))))
    let center = min(width - 1, max(0, Int((points[11].x + points[19].x) * 0.5 * Float(width - 1))))
    guard alpha[row * width + center] > 100 else { return (points[11].x, points[19].x) }
    var first = center, last = center
    while first > 0 && alpha[row * width + first - 1] > 100 { first -= 1 }
    while last + 1 < width && alpha[row * width + last + 1] > 100 { last += 1 }
    return (Float(first) / Float(width - 1), Float(last) / Float(width - 1))
  }
}

struct TryOnShape: Sendable {
  var mesh: TryOnMesh
  var needsRoom: Bool
  var belowHips: Bool
}

