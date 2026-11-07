import CoreML
import CoreGraphics
import UIKit

/// GarmentIQ HRNet preprocessing and quarter-pixel decoding, adapted under MIT.
/// See Vendor/GarmentIQ/NOTICE.md for the exact upstream revision and weights.
final class GarmentLandmarkDetector {
  private let model: MLModel

  init() throws {
    guard let url = Bundle.main.url(forResource: "GarmentLandmarks", withExtension: "mlmodelc") else { throw GarmentCaptureError.image }
    let configuration = MLModelConfiguration()
    #if targetEnvironment(simulator)
    configuration.computeUnits = .cpuOnly
    #else
    configuration.computeUnits = .all
    #endif
    model = try MLModel(contentsOf: url, configuration: configuration)
  }

  func detect(in image: CGImage) throws -> [CGPoint] {
    // Upstream uses a width-based affine transform, centered vertically, not aspect-fill.
    let w = 288, h = 384
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
          let buffer else { throw GarmentCaptureError.image }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw GarmentCaptureError.image }
    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let ratio = Double(w) / Double(image.width)
    let scaledHeight = Double(image.height) * ratio
    context.draw(image, in: CGRect(x: 0, y: (Double(h) - scaledHeight) / 2, width: Double(w), height: scaledHeight))
    let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
    let result = try model.prediction(from: input)
    guard let heatmaps = result.featureValue(for: "landmarks")?.multiArrayValue,
          heatmaps.shape.map(\.intValue) == [1, 25, 96, 72] else { throw GarmentCaptureError.image }
    let required = Set([1, 6, 11, 15, 19, 24])
    return try (0..<25).map { joint in
      func value(_ x: Int, _ y: Int) -> Double { heatmaps[[0, NSNumber(value: joint), NSNumber(value: y), NSNumber(value: x)]].doubleValue }
      var best = -Double.infinity, bx = 0, by = 0
      for y in 0..<96 { for x in 0..<72 {
        let candidate = value(x, y)
        if candidate > best { best = candidate; bx = x; by = y }
      } }
      guard best.isFinite, !required.contains(joint) || best > 0.45 else { throw GarmentCaptureError.unclear }
      var x = Double(bx), y = Double(by)
      if bx > 1, bx < 71, by > 1, by < 95 {
        x += value(bx + 1, by) == value(bx - 1, by) ? 0 : (value(bx + 1, by) > value(bx - 1, by) ? 0.25 : -0.25)
        y += value(bx, by + 1) == value(bx, by - 1) ? 0 : (value(bx, by + 1) > value(bx, by - 1) ? 0.25 : -0.25)
      }
      // Inverse of GarmentIQ's centered affine transform, expressed in image fractions.
      return CGPoint(x: x / 72, y: (y * 4 - (384 - scaledHeight) / 2) / scaledHeight)
    }
  }
}
