import CoreGraphics
import CryptoKit
import Foundation

struct GarmentImagePoint: Codable, Equatable, Sendable {
  var x: Double
  var y: Double
  var point: CGPoint { CGPoint(x: x, y: y) }
  var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

/// Observations already admitted by capture, tied to the exact upright PNG.
/// This is garment-only metadata, not body/face data or a fit authorization.
struct GarmentPatternEvidence: Codable, Equatable, Sendable {
  let version: Int
  let imageSHA256: String
  let points: [GarmentImagePoint]

  private init(imageSHA256: String, points: [GarmentImagePoint]) {
    version = 1
    self.imageSHA256 = imageSHA256
    self.points = points
  }

  var isValid: Bool {
    version == 1 && imageSHA256.count == 64
      && imageSHA256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
      && points.count == 25 && points.allSatisfy(\.isValid)
      && points[11].x < points[19].x && points[6].x < points[24].x
      && points[1].y < min(points[11].y, points[19].y)
      && points[15].y > max(points[11].y, points[19].y)
  }

  static func validate(image: Data, points: [CGPoint], outline: GarmentOutline) throws -> Self {
    guard !image.isEmpty, image.count <= 20_000_000, points.count == 25 else { throw GarmentCaptureError.shape }
    _ = try GarmentLandmarkValidation.validate(points, against: outline)
    let evidence = Self(imageSHA256: digest(image), points: points.map { GarmentImagePoint(x: $0.x, y: $0.y) })
    guard evidence.isValid else { throw GarmentCaptureError.shape }
    return evidence
  }

  func matches(_ image: Data) -> Bool { isValid && Self.digest(image) == imageSHA256 }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
