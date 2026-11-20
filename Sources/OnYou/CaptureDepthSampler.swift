import CoreVideo
import Foundation

enum CaptureDepthSampler {
  /// Small, confidence-filtered ROI for guidance only; scan admission has its own stricter checks.
  static func meters(_ depth: CVPixelBuffer?, confidence: CVPixelBuffer? = nil, mask: CVPixelBuffer? = nil,
                     center: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> Double? {
    guard center.x.isFinite, center.y.isFinite, (0...1).contains(center.x), (0...1).contains(center.y),
          let depth, CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
          CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(depth) else { return nil }
    let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth), stride = CVPixelBufferGetBytesPerRow(depth)
    guard width > 0, height > 0, stride >= width * 4, height <= CVPixelBufferGetDataSize(depth) / stride else { return nil }
    if let confidence {
      guard CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
            CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return nil }
    }
    defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
    if let mask {
      guard [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent32Float].contains(CVPixelBufferGetPixelFormatType(mask)),
            CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else { return nil }
    }
    defer { if let mask { CVPixelBufferUnlockBaseAddress(mask, .readOnly) } }
    func sampledValue(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Double? {
      guard let address = CVPixelBufferGetBaseAddress(buffer) else { return nil }
      let px = min(CVPixelBufferGetWidth(buffer) - 1, x * CVPixelBufferGetWidth(buffer) / width)
      let py = min(CVPixelBufferGetHeight(buffer) - 1, y * CVPixelBufferGetHeight(buffer) / height)
      let bytes = CVPixelBufferGetBytesPerRow(buffer)
      let isFloat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
      guard px >= 0, py >= 0, bytes >= CVPixelBufferGetWidth(buffer) * (isFloat ? 4 : 1),
            CVPixelBufferGetHeight(buffer) <= CVPixelBufferGetDataSize(buffer) / bytes else { return nil }
      let row = address.advanced(by: py * bytes)
      if isFloat {
        let result = row.assumingMemoryBound(to: Float.self)[px]
        return result.isFinite ? Double(result) : nil
      }
      return Double(row.assumingMemoryBound(to: UInt8.self)[px])
    }
    return withUnsafeTemporaryAllocation(of: Float.self, capacity: 81) { samples in
      var count = 0
      for row in 0..<9 { for column in 0..<9 {
        let u = center.x + Double(column - 4) / 20, v = center.y + Double(row - 4) / 20
        guard (0..<1).contains(u), (0..<1).contains(v) else { continue }
        let x = Int(u * Double(width)), y = Int(v * Double(height))
        if let confidence, (sampledValue(confidence, x: x, y: y) ?? 0) < 1 { continue }
        if let mask {
          let threshold = CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float ? 0.5 : 128.0
          if (sampledValue(mask, x: x, y: y) ?? 0) < threshold { continue }
        }
        let value = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)[x]
        if value.isFinite, (0.2...3).contains(value) { samples[count] = value; count += 1 }
      } }
      guard count >= 12 else { return nil }
      var valid = UnsafeMutableBufferPointer(start: samples.baseAddress, count: count)
      valid.sort()
      return Double(valid[count / 2])
    }
  }
}
