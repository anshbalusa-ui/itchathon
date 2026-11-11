import SwiftUI

struct BodyScanFloorGuide: View {
  var body: some View {
    GeometryReader { geometry in
      let side = min(geometry.size.width * 0.42, geometry.size.height * 0.3)
      Path { path in
        let frame = CGRect(x: (geometry.size.width - side) / 2, y: (geometry.size.height - side) / 2, width: side, height: side)
        let length: CGFloat = 18
        for (x, dx) in [(frame.minX, length), (frame.maxX, -length)] {
          for (y, dy) in [(frame.minY, length), (frame.maxY, -length)] {
            path.move(to: CGPoint(x: x + dx, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + dy))
          }
        }
      }
      .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }
  }
}
