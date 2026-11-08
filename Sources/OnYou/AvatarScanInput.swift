import CoreVideo
import Foundation

struct AvatarScanInput {
  private var imageURLs: Set<URL>
  private var depthImageURLs: Set<URL>

  init(imageURLs: Set<URL>, depthImageURLs: Set<URL>) {
    self.imageURLs = Set(imageURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL })
    self.depthImageURLs = Set(depthImageURLs.map { $0.resolvingSymlinksInPath().standardizedFileURL })
  }

  static func hasCoverage(images: Int, passes: Int) -> Bool { images >= 60 && passes >= 2 }

  func validate(passes: Int) throws -> Int {
    try validate(usedImages: imageURLs, passes: passes)
  }

  func validate(usedSampleIDs: Set<Int>, urlsBySample: [Int: URL], rejectedIDs: Set<Int>, passes: Int) throws -> Int {
    let acceptedIDs = usedSampleIDs.subtracting(rejectedIDs)
    let urls = acceptedIDs.compactMap { urlsBySample[$0]?.resolvingSymlinksInPath().standardizedFileURL }
    let used = Set(urls)
    guard used.count == acceptedIDs.count else { throw AvatarScanError.insufficientCoverage }
    return try validate(usedImages: used, passes: passes)
  }

  private func validate(usedImages: Set<URL>, passes: Int) throws -> Int {
    guard imageURLs.allSatisfy(\.isFileURL), usedImages.isSubset(of: imageURLs),
          depthImageURLs.isSubset(of: imageURLs) else { throw AvatarScanError.invalidModel }
    guard Self.hasCoverage(images: usedImages.count, passes: passes) else { throw AvatarScanError.insufficientCoverage }
    guard usedImages.intersection(depthImageURLs).count >= max(20, (usedImages.count + 1) / 2) else {
      throw AvatarScanError.missingDepth
    }
    return usedImages.count
  }

  static func containsFiniteDepth(_ buffer: CVPixelBuffer?) -> Bool {
    guard let buffer,
          [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32].contains(CVPixelBufferGetPixelFormatType(buffer)),
          CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    guard width > 0, height > 0, rowBytes > 0, rowBytes % MemoryLayout<Float>.stride == 0,
          width <= rowBytes / MemoryLayout<Float>.stride, height <= CVPixelBufferGetDataSize(buffer) / rowBytes,
          let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
    // shortcut: finite depth is only an input sanity check; validate accuracy with calibrated captures before using dimensions for fit.
    for y in 0..<height {
      let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
      for x in 0..<width where row[x].isFinite && row[x] > 0 { return true }
    }
    return false
  }
}
