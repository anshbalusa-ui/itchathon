import simd

extension TryOnSurface {
  /// Clothing uses the same convex envelope on both sides of the hip reference,
  /// so a connected concavity cannot create a sudden horizontal shelf. Above
  /// the hips only the observed torso is enclosed; below, cloth may span legs.
  /// The caller admits upper-body ray coverage before enclosing its contour.
  func garmentSection(at y: Float, bridgeBelow hips: Float, halfWidth: Float) -> [TryOnSegment] {
    guard let row = section(y) else { return [] }
    var points: [SIMD2<Float>] = []
    if y >= hips {
      guard let torso = row.torso else { return [] }
      points.reserveCapacity(torso.segments.count*2)
      for segment in torso.segments { points.append(segment.a); points.append(segment.b) }
    } else {
      for component in row.components where abs(component.center.x) < halfWidth {
        for segment in component.segments { points.append(segment.a); points.append(segment.b) }
      }
    }
    points.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
    guard points.count >= 3 else { return [] }
    func cross(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
      (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
    var low: [SIMD2<Float>] = [], high: [SIMD2<Float>] = []
    for point in points {
      while low.count >= 2 && cross(low[low.count - 2], low[low.count - 1], point) <= 0 { low.removeLast() }
      low.append(point)
    }
    for point in points.reversed() {
      while high.count >= 2 && cross(high[high.count - 2], high[high.count - 1], point) <= 0 { high.removeLast() }
      high.append(point)
    }
    low.removeLast(); high.removeLast()
    let hull = low + high
    guard hull.count >= 3 else { return [] }
    return hull.indices.map { TryOnSegment(a: hull[$0], b: hull[($0 + 1) % hull.count]) }
  }
}
