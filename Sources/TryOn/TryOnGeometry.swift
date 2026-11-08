import Foundation
import simd

struct TryOnMesh: Sendable {
  var positions: [SIMD3<Float>]
  var textureCoordinates: [SIMD2<Float>]
  var front: [UInt32]
  var back: [UInt32]
}

struct TryOnTriangle: Sendable {
  var a: SIMD3<Float>
  var b: SIMD3<Float>
  var c: SIMD3<Float>
}

struct TryOnSurface: Sendable {
  var triangles: [TryOnTriangle]

  func section(at y: Float) -> [TryOnSegment] {
    var segments: [TryOnSegment] = []
    for triangle in triangles {
      let points = [triangle.a, triangle.b, triangle.c]
      var hits: [SIMD2<Float>] = []
      for i in 0..<3 {
        let a = points[i], b = points[(i + 1) % 3]
        if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
          let p = a + (b - a) * ((y - a.y) / (b.y - a.y))
          hits.append(SIMD2(p.x, p.z))
        }
      }
      if hits.count == 2 { segments.append(TryOnSegment(a: hits[0], b: hits[1])) }
    }
    return segments
  }

  func depth(x: Float, y: Float) -> (front: Float, back: Float)? {
    Self.depth(x: x, segments: section(at: y))
  }

  static func depth(x: Float, segments: [TryOnSegment]) -> (front: Float, back: Float)? {
    var values: [Float] = []
    for segment in segments {
      let dx = segment.b.x - segment.a.x
      guard abs(dx) > 0.00001 else { continue }
      let t = (x - segment.a.x) / dx
      if (0...1).contains(t) { values.append(segment.a.y + (segment.b.y - segment.a.y) * t) }
    }
    guard let front = values.max(), let back = values.min(), front - back > 0.01 else { return nil }
    return (front, back)
  }
}

struct TryOnSegment: Sendable {
  var a: SIMD2<Float>
  var b: SIMD2<Float>
}

struct TryOnRing: Sendable {
  var points: [SIMD2<Float>]
  var requiredPerimeter: Float
  var tight: Bool

  static func make(segments: [TryOnSegment], centerX: Float, shoulderWidth: Float, circumference: Float) throws -> Self {
    guard circumference.isFinite, circumference > 0, centerX.isFinite, shoulderWidth > 0 else { throw TryOnError.geometry }
    let central = segments.flatMap { [$0.a, $0.b] }.filter { abs($0.x - centerX) < shoulderWidth * 0.2 }
    guard let front = central.map(\.y).max(), let back = central.map(\.y).min(), front - back > 0.025 else { throw TryOnError.surface }
    let center = SIMD2(centerX, (front + back) / 2)
    let count = 64
    var radii: [Float?] = []
    for i in 0..<count {
      let angle = Float(i) * 2 * .pi / Float(count)
      let direction = SIMD2(sin(angle), cos(angle))
      var nearest = Float.infinity
      for edge in segments {
        let v = edge.b - edge.a
        let denominator = cross(direction, v)
        guard abs(denominator) > 0.000001 else { continue }
        let t = cross(edge.a - center, v) / denominator
        let u = cross(edge.a - center, direction) / denominator
        if t > 0.005 && (0...1).contains(u) { nearest = min(nearest, t) }
      }
      radii.append(nearest.isFinite ? nearest : nil)
    }
    guard radii.compactMap({ $0 }).count >= count - 4 else { throw TryOnError.surface }
    for i in 0..<count where radii[i] == nil {
      guard let left = (1...4).first(where: { radii[(i - $0 + count) % count] != nil }),
            let right = (1...4).first(where: { radii[(i + $0) % count] != nil }), left + right <= 5 else { throw TryOnError.surface }
      let a = radii[(i - left + count) % count]!, b = radii[(i + right) % count]!
      radii[i] = a + (b - a) * Float(left) / Float(left + right)
    }
    let observed = radii.map { $0! }
    func points(offset: Float) -> [SIMD2<Float>] {
      observed.enumerated().map { i, radius in
        let angle = Float(i) * 2 * .pi / Float(count)
        return center + SIMD2(sin(angle), cos(angle)) * (radius + offset)
      }
    }
    let required = perimeter(points(offset: 0))
    var low: Float = 0.006, high: Float = 0.25
    for _ in 0..<20 {
      let middle = (low + high) / 2
      if perimeter(points(offset: middle)) < circumference { low = middle } else { high = middle }
    }
    return Self(points: points(offset: low), requiredPerimeter: required, tight: circumference < required + 0.02)
  }

  func sample(_ u: Float, front: Bool) -> SIMD2<Float> {
    let count = points.count
    let half = count / 2, left = count * 3 / 4
    let path = (0...half).map { i in points[(left + (front ? i : -i) + count) % count] }
    let lengths = (0..<half).map { simd_distance(path[$0], path[$0 + 1]) }
    let target = min(1, max(0, u)) * lengths.reduce(0, +)
    var walked: Float = 0
    for i in 0..<half {
      if walked + lengths[i] >= target {
        return simd_mix(path[i], path[i + 1], SIMD2(repeating: (target - walked) / max(0.000001, lengths[i])))
      }
      walked += lengths[i]
    }
    return path[half]
  }

  private static func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
  private static func perimeter(_ points: [SIMD2<Float>]) -> Float {
    points.indices.reduce(0) { $0 + simd_distance(points[$1], points[($1 + 1) % points.count]) }
  }
}

struct TryOnBodyPose: Sendable {
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

  func opaque(_ uv: SIMD2<Float>) -> Bool {
    let x = min(width - 1, max(0, Int(uv.x * Float(width - 1))))
    let y = min(height - 1, max(0, Int(uv.y * Float(height - 1))))
    return alpha[y * width + x] > 100
  }

  func bodyEdges(at y: Float) -> (Float, Float) {
    let row = min(height - 1, max(0, Int(y * Float(height - 1))))
    let columns = (0..<width).filter { alpha[row * width + $0] > 100 }
    if let first = columns.first, let last = columns.last, last > first {
      return (Float(first) / Float(width - 1), Float(last) / Float(width - 1))
    }
    return (points[11].x, points[19].x)
  }
}

struct TryOnShape: Sendable {
  var mesh: TryOnMesh
  var needsRoom: Bool
  var belowHips: Bool
  var chestAllowance: Float
}

enum TryOnGeometry {
  static func build(surface: TryOnSurface, pose: TryOnBodyPose, pattern: TryOnPattern, dimensions: GarmentScanDimensions) throws -> TryOnShape {
    guard dimensions.isValid, pattern.points.count == 25, pattern.width > 1, pattern.height > 1,
          pattern.alpha.count == pattern.width * pattern.height else { throw TryOnError.shirt }
    let p = pattern.points
    guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (-0.05...1.05).contains($0.x) && (-0.05...1.05).contains($0.y) }),
          p[19].x - p[11].x > 0.2, p[15].y - p[1].y > 0.4 else { throw TryOnError.shirt }
    let meterX = Float(dimensions.bodyWidthM) / (p[19].x - p[11].x)
    let meterY = Float(dimensions.lengthM) / (p[15].y - p[1].y)
    let imageCenter = (p[1].x + p[5].x) / 2
    let shoulderWidth = abs(pose.leftShoulder.x - pose.rightShoulder.x)
    guard (0.16...0.7).contains(shoulderWidth), pose.neck.y > pose.hips.y + 0.15 else { throw TryOnError.pose }
    let armpit = max(p[11].y, p[19].y)
    let columns = 80, rows = 100
    var frontPositions: [SIMD3<Float>] = [], backPositions: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var tight = false, chestAllowance: Float = 0
    let leftSleeve = Sleeve(shoulder: p[6], armpit: p[11], outer: p[8], inner: p[9],
                            bodyShoulder: pose.rightShoulder, bodyElbow: pose.rightElbow, meterX: meterX, meterY: meterY, surface: surface)
    let rightSleeve = Sleeve(shoulder: p[24], armpit: p[19], outer: p[22], inner: p[21],
                             bodyShoulder: pose.leftShoulder, bodyElbow: pose.leftElbow, meterX: meterX, meterY: meterY, surface: surface)
    for row in 0...rows {
      let v = Float(row) / Float(rows)
      let y = pose.neck.y - (v - p[1].y) * meterY
      let sampleY = max(pose.hips.y + 0.025, min(pose.neck.y - 0.025, y))
      let segments = surface.section(at: sampleY)
      let fraction = min(1, max(0, (pose.neck.y - sampleY) / (pose.neck.y - pose.hips.y)))
      let centerX = pose.neck.x + (pose.hips.x - pose.neck.x) * fraction
      let edges: (Float, Float)
      if v < armpit {
        let t = min(1, max(0, (v - p[6].y) / max(0.01, armpit - p[6].y)))
        edges = (p[6].x + (p[11].x - p[6].x) * t, p[24].x + (p[19].x - p[24].x) * t)
      } else { edges = pattern.bodyEdges(at: min(v, p[15].y - 0.015)) }
      let circumference = max(0.15, (edges.1 - edges.0) * meterX * 2)
      let ring = try TryOnRing.make(segments: segments, centerX: centerX, shoulderWidth: shoulderWidth, circumference: circumference)
      if abs(v - armpit) < 0.012 { chestAllowance = Float(dimensions.bodyWidthM) * 2 - ring.requiredPerimeter }
      if v >= armpit && y >= pose.hips.y { tight = tight || ring.tight }
      for column in 0...columns {
        let u = Float(column) / Float(columns)
        let photoUV = SIMD2(u, v)
        let bodyU = (u - edges.0) / max(0.01, edges.1 - edges.0)
        func position(front: Bool) -> SIMD3<Float> {
          let section = ring.sample(bodyU, front: front)
          var point = SIMD3(section.x, y, section.y)
          // The open upper panels lie over observed shoulders rather than an inflated neck cylinder.
          let upper = 1 - smooth((v - p[1].y) / max(0.01, armpit - p[1].y))
          let flatX = centerX + (u - imageCenter) * meterX
          if upper > 0, let depth = TryOnSurface.depth(x: flatX, segments: segments) {
            let projected = SIMD3(flatX, y, front ? depth.front + 0.008 : depth.back - 0.008)
            point = simd_mix(point, projected, SIMD3(repeating: upper))
          }
          if u < edges.0 && v < armpit + 0.05 {
            point = leftSleeve.warp(photoUV, from: point, front: front)
          } else if u > edges.1 && v < armpit + 0.05 {
            point = rightSleeve.warp(photoUV, from: point, front: front)
          }
          return point
        }
        frontPositions.append(position(front: true)); backPositions.append(position(front: false)); uv.append(photoUV)
      }
    }
    var front: [UInt32] = [], back: [UInt32] = []
    let offset = UInt32(frontPositions.count)
    var edges: [Edge: Int] = [:]
    func add(_ a: Int, _ b: Int, _ c: Int) {
      let center = (uv[a] + uv[b] + uv[c]) / 3
      guard pattern.opaque(center), [a,b,c].filter({ pattern.opaque(uv[$0]) }).count >= 2 else { return }
      front += [UInt32(a),UInt32(b),UInt32(c)]
      back += [UInt32(c)+offset,UInt32(b)+offset,UInt32(a)+offset]
      for (x,y) in [(a,b),(b,c),(c,a)] { edges[Edge(x,y), default: 0] += 1 }
    }
    for y in 0..<rows { for x in 0..<columns {
      let a = y * (columns + 1) + x, b = a + 1, c = a + columns + 1, d = c + 1
      add(a,c,b); add(b,c,d)
    } }
    for (edge,count) in edges where count == 1 {
      let center = (uv[edge.a] + uv[edge.b]) / 2
      let collar = center.y < armpit * 0.6 && center.x > p[1].x - 0.03 && center.x < p[5].x + 0.03
      let cuff = (center.x < p[11].x - 0.03 || center.x > p[19].x + 0.03) && center.y < armpit + 0.04
      guard !collar, !cuff, center.y < p[15].y - 0.035 else { continue }
      let a = UInt32(edge.a), b = UInt32(edge.b)
      back += [a,b,a+offset,b,b+offset,a+offset]
    }
    let positions = frontPositions + backPositions
    guard !front.isEmpty, positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { throw TryOnError.geometry }
    return TryOnShape(mesh: TryOnMesh(positions: positions, textureCoordinates: uv + uv, front: front, back: back),
                      needsRoom: tight, belowHips: pose.neck.y - Float(dimensions.lengthM) < pose.hips.y,
                      chestAllowance: chestAllowance)
  }

  private static func smooth(_ value: Float) -> Float { let x = min(1, max(0, value)); return x*x*(3-2*x) }

  private struct Edge: Hashable {
    var a: Int
    var b: Int
    init(_ x: Int, _ y: Int) { a = min(x,y); b = max(x,y) }
  }

  private struct Sleeve {
    var origin: SIMD2<Float>
    var axis: SIMD2<Float>
    var perpendicular: SIMD2<Float>
    var bodyOrigin: SIMD3<Float>
    var bodyAxis: SIMD3<Float>
    var side: SIMD3<Float>
    var outward: SIMD3<Float>
    var radius: Float
    var meterX: Float
    var meterY: Float

    init(shoulder: SIMD2<Float>, armpit: SIMD2<Float>, outer: SIMD2<Float>, inner: SIMD2<Float>,
         bodyShoulder: SIMD3<Float>, bodyElbow: SIMD3<Float>, meterX: Float, meterY: Float, surface: TryOnSurface) {
      func flat(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x * meterX, -p.y * meterY) }
      origin = (flat(shoulder) + flat(armpit)) / 2
      let cuff = (flat(outer) + flat(inner)) / 2
      axis = simd_normalize(cuff - origin)
      perpendicular = SIMD2(-axis.y, axis.x)
      bodyOrigin = bodyShoulder
      bodyAxis = simd_normalize(bodyElbow - bodyShoulder)
      side = simd_normalize(SIMD3(-bodyAxis.y, bodyAxis.x, 0))
      outward = simd_normalize(simd_cross(side, bodyAxis))
      if outward.z < 0 { outward = -outward }
      let middle = bodyShoulder + bodyAxis * simd_distance(cuff, origin) * 0.7
      let observed = surface.depth(x: middle.x, y: middle.y).map { ($0.front - $0.back) / 2 + 0.008 } ?? 0
      radius = max(simd_distance(flat(outer), flat(inner)) / .pi, observed)
      self.meterX = meterX; self.meterY = meterY
    }

    func warp(_ uv: SIMD2<Float>, from point: SIMD3<Float>, front: Bool) -> SIMD3<Float> {
      let delta = SIMD2(uv.x * meterX, -uv.y * meterY) - origin
      let distance = simd_dot(delta, axis)
      let cross = simd_dot(delta, perpendicular)
      let angle = min(.pi/2, max(-.pi/2, cross / max(0.02, radius)))
      let center = bodyOrigin + bodyAxis * max(0, distance)
      let target = center + side * (radius * sin(angle)) + outward * (radius * cos(angle) * (front ? 1 : -1))
      let blend = TryOnGeometry.smooth(distance / 0.055)
      return simd_mix(point, target, SIMD3(repeating: blend))
    }
  }
}
