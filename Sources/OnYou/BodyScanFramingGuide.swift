import SwiftUI

struct BodyScanFramingGuide: Shape {
  var showOutline: Bool

  func path(in rect: CGRect) -> Path {
    let frame = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.06)
    var path = Path()
    guard showOutline else {
      for x in [frame.minX, frame.maxX] {
        for y in [frame.minY, frame.maxY] {
          let dx: CGFloat = x == frame.minX ? 1 : -1
          let dy: CGFloat = y == frame.minY ? 1 : -1
          path.move(to: CGPoint(x: x + dx * 30, y: y))
          path.addCurve(to: CGPoint(x: x, y: y + dy * 30),
                        control1: CGPoint(x: x + dx * 8, y: y),
                        control2: CGPoint(x: x, y: y + dy * 8))
        }
      }
      return path
    }

    let width = min(frame.width, frame.height * 0.58)
    func point(_ p: CGPoint) -> CGPoint {
      CGPoint(x: frame.midX + (p.x - 0.5) * width, y: frame.minY + p.y * frame.height)
    }
    // One curved half, reflected in reverse, keeps the neck, fingertips and toes continuous.
    let curves: [(end: CGPoint, first: CGPoint, second: CGPoint)] = [
      (.init(x: 0.59, y: 0.07), .init(x: 0.56, y: 0), .init(x: 0.60, y: 0.025)),
      (.init(x: 0.56, y: 0.145), .init(x: 0.59, y: 0.11), .init(x: 0.56, y: 0.12)),
      (.init(x: 0.70, y: 0.19), .init(x: 0.56, y: 0.17), .init(x: 0.66, y: 0.17)),
      (.init(x: 0.79, y: 0.32), .init(x: 0.75, y: 0.21), .init(x: 0.76, y: 0.27)),
      (.init(x: 0.86, y: 0.45), .init(x: 0.81, y: 0.37), .init(x: 0.84, y: 0.42)),
      (.init(x: 0.90, y: 0.52), .init(x: 0.88, y: 0.48), .init(x: 0.91, y: 0.49)),
      (.init(x: 0.86, y: 0.55), .init(x: 0.90, y: 0.545), .init(x: 0.88, y: 0.56)),
      (.init(x: 0.82, y: 0.50), .init(x: 0.84, y: 0.54), .init(x: 0.82, y: 0.52)),
      (.init(x: 0.74, y: 0.39), .init(x: 0.81, y: 0.47), .init(x: 0.76, y: 0.43)),
      (.init(x: 0.67, y: 0.30), .init(x: 0.72, y: 0.36), .init(x: 0.68, y: 0.29)),
      (.init(x: 0.64, y: 0.46), .init(x: 0.66, y: 0.31), .init(x: 0.63, y: 0.40)),
      (.init(x: 0.68, y: 0.59), .init(x: 0.64, y: 0.51), .init(x: 0.68, y: 0.54)),
      (.init(x: 0.65, y: 0.75), .init(x: 0.68, y: 0.65), .init(x: 0.66, y: 0.70)),
      (.init(x: 0.61, y: 0.94), .init(x: 0.64, y: 0.82), .init(x: 0.60, y: 0.90)),
      (.init(x: 0.67, y: 0.975), .init(x: 0.62, y: 0.96), .init(x: 0.67, y: 0.96)),
      (.init(x: 0.58, y: 0.995), .init(x: 0.68, y: 0.995), .init(x: 0.62, y: 0.995)),
      (.init(x: 0.55, y: 0.94), .init(x: 0.55, y: 0.995), .init(x: 0.55, y: 0.96)),
      (.init(x: 0.53, y: 0.77), .init(x: 0.55, y: 0.89), .init(x: 0.54, y: 0.82)),
      (.init(x: 0.50, y: 0.65), .init(x: 0.52, y: 0.71), .init(x: 0.52, y: 0.65))
    ]
    let top = CGPoint(x: 0.5, y: 0)
    path.move(to: point(top))
    for curve in curves {
      path.addCurve(to: point(curve.end), control1: point(curve.first), control2: point(curve.second))
    }
    func mirror(_ p: CGPoint) -> CGPoint { point(CGPoint(x: 1 - p.x, y: p.y)) }
    for index in curves.indices.reversed() {
      path.addCurve(to: mirror(index == 0 ? top : curves[index - 1].end),
                    control1: mirror(curves[index].second), control2: mirror(curves[index].first))
    }
    path.closeSubpath()
    return path
  }
}
