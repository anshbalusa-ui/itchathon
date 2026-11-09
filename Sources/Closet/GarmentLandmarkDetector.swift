import CoreML
import CoreGraphics
import UIKit

struct GarmentLandmarkTiming: Sendable {
  var modelLoadMS: Double = 0
  var preprocessingMS: Double = 0
  var predictionMS: Double = 0
  var decodingMS: Double = 0
  var totalMS: Double { modelLoadMS + preprocessingMS + predictionMS + decodingMS }
}

struct GarmentLandmarkDetection: Sendable {
  var points: [CGPoint]
  var timing: GarmentLandmarkTiming
}

/// One model and one prediction at a time across capture and try-on. No photos or
/// observations survive the call. Camera cancellation is checked after native inference.
actor GarmentLandmarkService {
  static let shared = GarmentLandmarkService()
  private var detector: GarmentLandmarkDetector?

  func detect(in image: CGImage) throws -> GarmentLandmarkDetection {
    try Task.checkCancellation()
    var loadMS = 0.0
    if detector == nil {
      let start = ProcessInfo.processInfo.systemUptime
      detector = try GarmentLandmarkDetector()
      loadMS = (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    guard let detector else { throw GarmentCaptureError.image }
    var result = try detector.detectTimed(in: image)
    result.timing.modelLoadMS = loadMS
    try Task.checkCancellation()
    return result
  }
}

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

  func detect(in image: CGImage) throws -> [CGPoint] { try detectTimed(in: image).points }

  func detectTimed(in image: CGImage) throws -> GarmentLandmarkDetection {
    let start = ProcessInfo.processInfo.systemUptime
    // Upstream uses a width-based affine transform, centered vertically, not aspect-fill.
    let width = 288, height = 384
    var buffer: CVPixelBuffer?
    let attributes = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
    guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
          let buffer else { throw GarmentCaptureError.image }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw GarmentCaptureError.image }
    context.setFillColor(UIColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let ratio = Double(width) / Double(image.width)
    let scaledHeight = Double(image.height) * ratio
    context.draw(image, in: CGRect(x: 0, y: (Double(height) - scaledHeight) / 2, width: Double(width), height: scaledHeight))
    let input = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)])
    let ready = ProcessInfo.processInfo.systemUptime
    let result = try model.prediction(from: input)
    let predicted = ProcessInfo.processInfo.systemUptime
    guard let heatmaps = result.featureValue(for: "landmarks")?.multiArrayValue,
          heatmaps.shape.map(\.intValue) == [1, 25, 96, 72],
          heatmaps.strides.count == 4, heatmaps.strides.allSatisfy({ $0.intValue > 0 }) else { throw GarmentCaptureError.image }
    let points: [CGPoint]
    switch heatmaps.dataType {
    case .float32:
      points = try decode(heatmaps.dataPointer.assumingMemoryBound(to: Float.self), strides: heatmaps.strides, scaledHeight: scaledHeight)
    case .double:
      points = try decode(heatmaps.dataPointer.assumingMemoryBound(to: Double.self), strides: heatmaps.strides, scaledHeight: scaledHeight)
    case .float16:
      points = try decode(heatmaps.dataPointer.assumingMemoryBound(to: Float16.self), strides: heatmaps.strides, scaledHeight: scaledHeight)
    default:
      throw GarmentCaptureError.image
    }
    return GarmentLandmarkDetection(points: points, timing: GarmentLandmarkTiming(
      preprocessingMS: (ready - start) * 1000,
      predictionMS: (predicted - ready) * 1000,
      decodingMS: (ProcessInfo.processInfo.systemUptime - predicted) * 1000))
  }

  private func decode<T: BinaryFloatingPoint>(_ values: UnsafePointer<T>, strides: [NSNumber], scaledHeight: Double) throws -> [CGPoint] {
    let channelStride = strides[1].intValue, rowStride = strides[2].intValue, columnStride = strides[3].intValue
    var points: [CGPoint] = []
    points.reserveCapacity(25)
    for joint in 0..<25 {
      let channel = values.advanced(by: joint * channelStride)
      var best = -Double.infinity, bx = 0, by = 0
      for y in 0..<96 {
        let row = channel.advanced(by: y * rowStride)
        for x in 0..<72 {
          let candidate = Double(row[x * columnStride])
          if candidate > best { best = candidate; bx = x; by = y }
        }
      }
      switch joint {
      case 1, 6, 11, 15, 19, 24:
        guard best.isFinite, best > 0.45 else { throw GarmentCaptureError.unclear }
      default:
        guard best.isFinite else { throw GarmentCaptureError.unclear }
      }
      var x = Double(bx), y = Double(by)
      if bx > 1, bx < 71, by > 1, by < 95 {
        let left = channel[by * rowStride + (bx - 1) * columnStride]
        let right = channel[by * rowStride + (bx + 1) * columnStride]
        let above = channel[(by - 1) * rowStride + bx * columnStride]
        let below = channel[(by + 1) * rowStride + bx * columnStride]
        x += right == left ? 0 : (right > left ? 0.25 : -0.25)
        y += below == above ? 0 : (below > above ? 0.25 : -0.25)
      }
      // Same inverse affine transform and admission as the upstream model.
      points.append(CGPoint(x: x / 72, y: (y * 4 - (384 - scaledHeight) / 2) / scaledHeight))
    }
    return points
  }
}
