import Foundation

/// Conservative silhouette recognition for a flat, upright short-sleeved shirt.
/// These are visible extents, not inferred seams or tailoring measurements.
struct GarmentOutline {
  var widthLeft: CGPoint
  var widthRight: CGPoint
  var top: CGPoint
  var bottom: CGPoint
  var sleeveLeft: CGPoint
  var sleeveRight: CGPoint
  var bounds: CGRect

  static func detect(mask: [UInt8], width: Int, height: Int) throws -> Self {
    guard width >= 64, height >= 64, mask.count == width * height else { throw GarmentCaptureError.unclear }
    var rows: [(y: Int, left: Int, right: Int, count: Int)] = []
    for y in 0..<height {
      var left = width, right = -1, count = 0
      for x in 0..<width where mask[y * width + x] > 180 {
        left = min(left, x); right = max(right, x); count += 1
      }
      if count >= 5 { rows.append((y, left, right, count)) }
    }
    guard let first = rows.first, let last = rows.last, rows.count > height / 3 else { throw GarmentCaptureError.unclear }
    let left = rows.map(\.left).min()!, right = rows.map(\.right).max()!
    let h = last.y - first.y, w = right - left
    guard first.y > height / 30, last.y < height * 29 / 30,
          left > width / 30, right < width * 29 / 30 else { throw GarmentCaptureError.framing }
    let torso = rows.filter { $0.y >= first.y + h * 55 / 100 && $0.y <= first.y + h * 82 / 100 }
    guard torso.count > h / 5 else { throw GarmentCaptureError.shape }
    let sorted = torso.sorted { ($0.right - $0.left) < ($1.right - $1.left) }
    let mid = sorted[sorted.count / 2]
    let torsoWidth = mid.right - mid.left
    let center = (mid.left + mid.right) / 2
    guard torso.allSatisfy({
      abs(($0.right - $0.left) - torsoWidth) < torsoWidth / 8
        && abs(($0.right + $0.left) / 2 - center) < max(3, torsoWidth / 12)
        && $0.count > ($0.right - $0.left) * 9 / 10
    }), Double(h) / Double(torsoWidth) > 0.85, Double(h) / Double(torsoWidth) < 2.5,
      Double(w) / Double(torsoWidth) > 1.2, Double(w) / Double(torsoWidth) < 2.4 else { throw GarmentCaptureError.shape }
    let upper = rows.filter { $0.y < first.y + h * 45 / 100 }
    guard let sleeve = upper.max(by: { $0.right - $0.left < $1.right - $1.left }),
          abs((sleeve.left + sleeve.right) / 2 - center) < torsoWidth / 10 else { throw GarmentCaptureError.shape }
    let neck = (first.y...min(last.y, first.y + h / 5)).first { y in mask[y * width + center] > 180 }
    guard let neck, neck - first.y >= max(2, h / 40), neck - first.y < h / 5 else { throw GarmentCaptureError.shape }
    func point(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: Double(x) / Double(width), y: Double(y) / Double(height)) }
    return Self(widthLeft: point(mid.left, mid.y), widthRight: point(mid.right, mid.y),
                top: point(center, first.y), bottom: point(center, last.y),
                sleeveLeft: point(sleeve.left, sleeve.y), sleeveRight: point(sleeve.right, sleeve.y),
                bounds: CGRect(x: Double(left) / Double(width), y: Double(first.y) / Double(height),
                               width: Double(w) / Double(width), height: Double(h) / Double(height)))
  }
}
