import SceneKit
import simd

struct TryOnSourceMesh {
  var points: [SIMD3<Float>]
  var triangles: [(Int, Int, Int)]
}

/// Metric, Y-up coordinates after the saved scene's complete transform hierarchy.
/// Cross-sections are observed triangle intersections, never bounding-box depth.
final class TryOnSurface {

  struct Component {
    var segments: [TryOnSegment]
    var minX: Float
    var maxX: Float
    var minimumZ: Float
    var maximumZ: Float
    var depthColumns: [[Int]] = []
    private static let columnWidth: Float = 0.004

    mutating func indexDepth(remaining: inout Int) {
      guard width > 0,width < 8 else { return }
      let count = Int(ceil(width/Self.columnWidth))+1
      var entries = 0
      for segment in segments {
        entries += Int(ceil((segment.maxX-segment.minX)/Self.columnWidth))+4
        if entries > remaining { return }
      }
      remaining -= entries
      depthColumns = Array(repeating: [],count: count)
      for (index,segment) in segments.enumerated() {
        let first = max(0,Int(floor((segment.minX-minX)/Self.columnWidth))-1)
        let last = min(count-1,Int(ceil((segment.maxX-minX)/Self.columnWidth))+1)
        if first <= last { for column in first...last { depthColumns[column].append(index) } }
      }
    }
    var center: SIMD2<Float> { SIMD2((minX + maxX) / 2, (minimumZ + maximumZ) / 2) }
    var width: Float { maxX - minX }
    var perimeter: Float { segments.reduce(0) { $0 + simd_distance($1.a, $1.b) } }

    func depth(at x: Float) -> (front: Float, back: Float)? {
      guard x.isFinite,x >= minX,x <= maxX else { return nil }
      var front = -Float.greatestFiniteMagnitude, back = Float.greatestFiniteMagnitude
      var hits = 0
      func intersect(_ segment: TryOnSegment) {
        let delta = segment.b.x - segment.a.x
        guard abs(delta) > 1e-8 else { return }
        let t = (x - segment.a.x) / delta
        if t >= -0.0001 && t <= 1.0001 {
          let z = segment.a.y + t * (segment.b.y - segment.a.y)
          front = max(front, z); back = min(back, z); hits += 1
        }
      }
      if depthColumns.isEmpty {
        for segment in segments { intersect(segment) }
      } else {
        let column = min(depthColumns.count-1,max(0,Int(floor((x-minX)/Self.columnWidth))))
        for index in depthColumns[column] { intersect(segments[index]) }
      }
      guard hits >= 2, front - back > 0.001 else { return nil }
      return (front, back)
    }
  }

  struct Section {
    var y: Float
    var components: [Component]
    var torso: Component? {
      components.lazy.filter { $0.width > 0.025 }.min { abs($0.center.x) < abs($1.center.x) }
    }
  }

  let points: [SIMD3<Float>]
  let triangles: [(Int, Int, Int)]
  let minimum: SIMD3<Float>
  let maximum: SIMD3<Float>
  private let rowStep: Float = 0.003
  private var triangleRows: [[Int]] = []
  private var sections: [Int: Section] = [:]
  private var depthIndexRemaining = 4_000_000
  private(set) var computedSections = 0
  private(set) var testedTriangles = 0

  init(points: [SIMD3<Float>], triangles: [(Int, Int, Int)]) throws {
    guard points.count >= 20, points.count <= 3_000_000, triangles.count >= 100, triangles.count <= 500_000,
          points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }),
          triangles.allSatisfy({ points.indices.contains($0.0) && points.indices.contains($0.1) && points.indices.contains($0.2) }) else { throw TryOnError.body }
    self.points = points; self.triangles = triangles
    minimum = points.reduce(SIMD3(repeating: Float.greatestFiniteMagnitude), simd_min)
    maximum = points.reduce(SIMD3(repeating: -Float.greatestFiniteMagnitude), simd_max)
    guard maximum.y - minimum.y > 0.8, maximum.y - minimum.y < 2.5 else { throw TryOnError.body }
    triangleRows = Array(repeating: [], count: Int(ceil((maximum.y - minimum.y) / rowStep)) + 1)
    var indexedEntries = 0
    for (index, triangle) in triangles.enumerated() {
      if index % 4096 == 0 { try Task.checkCancellation() }
      let a = points[triangle.0].y, b = points[triangle.1].y, c = points[triangle.2].y
      let first = max(0, Int(floor((min(a, min(b, c)) - minimum.y) / rowStep)))
      let last = min(triangleRows.count - 1, Int(ceil((max(a, max(b, c)) - minimum.y) / rowStep)))
      if first <= last {
        let span = last - first + 1
        guard indexedEntries <= 4_000_000 - span else { throw TryOnError.body }
        indexedEntries += span
        for row in first...last { triangleRows[row].append(index) }
      }
    }
  }

  static func extract(_ root: SCNNode) throws -> TryOnSourceMesh {
    var points: [SIMD3<Float>] = [], triangles: [(Int, Int, Int)] = []
    var failed = false
    func append(_ node: SCNNode) {
      guard let geometry = node.geometry else { return }
      guard let source = geometry.sources(for: .vertex).first, source.usesFloatComponents,
            source.componentsPerVector >= 3, [4, 8].contains(source.bytesPerComponent),
            source.vectorCount > 0, source.vectorCount <= 250_000,
            source.dataStride >= source.bytesPerComponent * 3, source.dataStride <= source.data.count,
            source.dataOffset >= 0, source.dataOffset <= source.data.count - 3 * source.bytesPerComponent,
            source.vectorCount - 1 <= (source.data.count - source.dataOffset - 3 * source.bytesPerComponent) / source.dataStride else { failed = true; return }
      let base = points.count
      // Apply the complete saved normalization hierarchy before the clone is
      // attached under its separate canonical-yaw render owner.
      var world = node.simdTransform
      var ancestor = node.parent
      while let parent = ancestor { world = parent.simdTransform*world; ancestor = parent.parent }
      source.data.withUnsafeBytes { raw in
        for i in 0..<source.vectorCount {
          let offset = source.dataOffset + i * source.dataStride
          func value(_ component: Int) -> Float {
            let position = offset + component * source.bytesPerComponent
            return source.bytesPerComponent == 4 ? raw.loadUnaligned(fromByteOffset: position, as: Float.self) : Float(raw.loadUnaligned(fromByteOffset: position, as: Double.self))
          }
          let point = world*SIMD4(value(0),value(1),value(2),1)
          guard abs(point.w-1) < 0.0001 else { failed = true; return }
          points.append(SIMD3(point.x,point.y,point.z))
        }
      }
      for element in geometry.elements {
        guard [1, 2, 4].contains(element.bytesPerIndex) else { failed = true; continue }
        guard element.primitiveCount >= 0, element.primitiveCount <= 500_000 else { failed = true; continue }
        guard element.primitiveType == .triangles || element.primitiveType == .triangleStrip else { failed = true; continue }
        let count = element.primitiveType == .triangles ? element.primitiveCount * 3 : element.primitiveCount + 2
        guard count * element.bytesPerIndex <= element.data.count else { failed = true; continue }
        element.data.withUnsafeBytes { raw in
          func index(_ i: Int) -> Int {
            let offset = i * element.bytesPerIndex
            switch element.bytesPerIndex {
            case 1: return Int(raw.load(fromByteOffset: offset, as: UInt8.self))
            case 2: return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            default: return Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
          }
          for face in 0..<element.primitiveCount {
            let start = element.primitiveType == .triangles ? face * 3 : face
            var a = index(start), b = index(start + 1)
            let c = index(start + 2)
            if element.primitiveType == .triangleStrip && face % 2 == 1 { swap(&a, &b) }
            guard a < source.vectorCount, b < source.vectorCount, c < source.vectorCount else { failed = true; continue }
            if a != b && a != c && b != c { triangles.append((base + a, base + b, base + c)) }
          }
        }
      }
    }
    append(root) // enumerateChildNodes does not include geometry on the root itself.
    root.enumerateChildNodes { node, _ in append(node) }
    guard !failed, !triangles.isEmpty, triangles.count <= 500_000 else { throw TryOnError.body }
    return TryOnSourceMesh(points: points, triangles: triangles)
  }

  func section(at y: Float) -> [TryOnSegment] { section(y)?.torso?.segments ?? [] }

  func section(_ y: Float) -> Section? {
    guard y.isFinite, y >= minimum.y, y <= maximum.y else { return nil }
    let key = min(triangleRows.count - 1, max(0, Int(round((y - minimum.y) / rowStep))))
    if let cached = sections[key] { return cached }
    let plane = min(maximum.y - 0.00001, minimum.y + Float(key) * rowStep)
    var segments: [TryOnSegment] = []
    for index in triangleRows[key] {
      testedTriangles += 1
      let triangle = triangles[index]
      let vertices = (points[triangle.0], points[triangle.1], points[triangle.2])
      var first: SIMD2<Float>?, second: SIMD2<Float>?
      func intersect(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
        guard (a.y <= plane && b.y > plane) || (b.y <= plane && a.y > plane) else { return }
        let point = a + (b - a) * ((plane - a.y) / (b.y - a.y))
        if first == nil { first = SIMD2(point.x, point.z) } else { second = SIMD2(point.x, point.z) }
      }
      intersect(vertices.0, vertices.1); intersect(vertices.1, vertices.2); intersect(vertices.2, vertices.0)
      if let first, let second, simd_distance_squared(first, second) > 1e-12 { segments.append(TryOnSegment(a: first, b: second)) }
    }
    // Components separated in X are the observed arms/torso, not one hull that
    // incorrectly treats the space between a torso and an arm as solid body.
    segments.sort { $0.minX < $1.minX }
    var components: [Component] = []
    for segment in segments {
      let loZ = min(segment.a.y, segment.b.y), hiZ = max(segment.a.y, segment.b.y)
      if let last = components.indices.last, segment.minX <= components[last].maxX + 0.0001 {
        components[last].segments.append(segment)
        components[last].maxX = max(components[last].maxX, segment.maxX)
        components[last].minimumZ = min(components[last].minimumZ, loZ)
        components[last].maximumZ = max(components[last].maximumZ, hiZ)
      } else {
        components.append(Component(segments: [segment], minX: segment.minX, maxX: segment.maxX, minimumZ: loZ, maximumZ: hiZ))
      }
    }
    for i in components.indices { components[i].indexDepth(remaining: &depthIndexRemaining) }
    let result = Section(y: plane, components: components)
    sections[key] = result; computedSections += 1
    return result
  }

  func depth(x: Float, y: Float) -> (front: Float, back: Float)? {
    guard let row = section(y) else { return nil }
    for component in row.components where x >= component.minX && x <= component.maxX {
      if let depth = component.depth(at: x) { return depth }
    }
    return nil
  }
}
