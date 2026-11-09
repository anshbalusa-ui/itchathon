import CoreImage
import ImageIO
import UIKit
import Vision

enum GarmentImageProcessor {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  static func normalized(_ data: Data) throws -> CGImage {
    guard data.count <= 30_000_000,
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1600
          ] as CFDictionary) else { throw GarmentCaptureError.image }
    return image
  }

  static func foreground(_ image: CGImage) throws -> (mask: CVPixelBuffer, cutout: Data) {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])
    guard let observation = request.results?.first, observation.allInstances.count == 1 else { throw GarmentCaptureError.unclear }
    let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
    // Retained keypoints, mask and stored photo must share the same canvas.
    let cutout = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
    let ciImage = CIImage(cvPixelBuffer: cutout)
    guard let rendered = context.createCGImage(ciImage, from: ciImage.extent),
          let data = UIImage(cgImage: rendered).pngData() else { throw GarmentCaptureError.image }
    return (mask, data)
  }

  static func importedPhoto(_ data: Data) throws -> Data {
    let image = try normalized(data)
    if let result = try? foreground(image) { return result.cutout }
    guard let result = UIImage(cgImage: image).pngData() else { throw GarmentCaptureError.image }
    return result
  }

  static func smallMask(_ mask: CVPixelBuffer) throws -> (bytes: [UInt8], width: Int, height: Int) {
    CVPixelBufferLockBaseAddress(mask, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(mask) else { throw GarmentCaptureError.unclear }
    let sourceW = CVPixelBufferGetWidth(mask), sourceH = CVPixelBufferGetHeight(mask)
    let w = 192, h = max(64, sourceH * w / sourceW), stride = CVPixelBufferGetBytesPerRow(mask)
    let format = CVPixelBufferGetPixelFormatType(mask)
    guard [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent32Float].contains(format) else { throw GarmentCaptureError.unclear }
    var pixels = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h { for x in 0..<w {
      let sx = x * sourceW / w, sy = y * sourceH / h
      if format == kCVPixelFormatType_OneComponent8 {
        pixels[y * w + x] = base.advanced(by: sy * stride).assumingMemoryBound(to: UInt8.self)[sx]
      } else {
        let value = base.advanced(by: sy * stride).assumingMemoryBound(to: Float.self)[sx]
        pixels[y * w + x] = value.isFinite ? UInt8(min(255, max(0, value * 255))) : 0
      }
    } }
    return (pixels, w, h)
  }
}
