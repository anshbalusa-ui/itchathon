import ARKit
import CoreImage
import CoreGraphics
import CoreMotion
import CoreVideo
import Foundation
import ImageIO
import RealityKit
import UniformTypeIdentifiers

struct BodyCaptureStoredSample {
  let sampleID: Int
  let imageURL: URL
  let depthURL: URL
  let maskURL: URL
  let azimuth: Double
  let fullBody: Bool
  let gravity: CMAcceleration
}

struct BodyCaptureArchive {
  let imageURLs: Set<URL>
  let depthImageURLs: Set<URL>
  let fullBodyImageURLs: Set<URL>
  let urlsBySample: [Int: URL]
  var sampleCount: Int { samples.count }
  let samples: [BodyCaptureStoredSample]
  let coverage: BodyCaptureCoverage
  let direction: Int
  let nextSampleID: Int
  private let hasDistinctSamples: Bool

  init(samples: [BodyCaptureStoredSample], coverage: BodyCaptureCoverage,
       direction: Int = 1, nextSampleID: Int? = nil) {
    self.samples = samples
    self.coverage = coverage
    self.direction = direction
    let highestID = samples.map(\.sampleID).max() ?? -1
    self.nextSampleID = max(nextSampleID ?? 0, highestID == Int.max ? Int.max : highestID + 1)
    var images = Set<URL>()
    var fullBodyImages = Set<URL>()
    var files = Set<URL>()
    var fileIdentities = Set<AnyHashable>()
    var mapping: [Int: URL] = [:]
    var distinct = true
    for sample in samples {
      if sample.sampleID < 0 || !sample.azimuth.isFinite ||
          !sample.gravity.x.isFinite || !sample.gravity.y.isFinite || !sample.gravity.z.isFinite ||
          mapping.updateValue(sample.imageURL, forKey: sample.sampleID) != nil {
        distinct = false
      }
      for url in [sample.imageURL, sample.depthURL, sample.maskURL] {
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, files.insert(file).inserted else {
          distinct = false
          continue
        }
        if let identity = (try? file.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? AnyHashable,
           !fileIdentities.insert(identity).inserted {
          distinct = false
        }
      }
      images.insert(sample.imageURL)
      if sample.fullBody { fullBodyImages.insert(sample.imageURL) }
    }
    imageURLs = images
    depthImageURLs = images // AvatarScanInput tracks which RGB images have paired real depth.
    fullBodyImageURLs = fullBodyImages
    urlsBySample = mapping
    hasDistinctSamples = distinct
  }

  func hasCoverage(sampleIDs: Set<Int>? = nil) -> Bool {
    hasDistinctSamples && coverage.hasCoverage(sampleIDs: sampleIDs)
  }

  func retaining(sampleIDs: Set<Int>) -> BodyCaptureArchive {
    let retained = samples.filter { sampleIDs.contains($0.sampleID) }
    return BodyCaptureArchive(samples: retained, coverage: coverage.retaining(sampleIDs: sampleIDs),
                              direction: direction, nextSampleID: nextSampleID)
  }

  func alignedCoverage(poses: [Int: BodyCaptureReconstructedPose],
                       rejectedIDs: Set<Int>) -> BodyCaptureAlignment {
    if hasDistinctSamples,
       poses.keys.allSatisfy({ urlsBySample[$0] != nil }),
       rejectedIDs.allSatisfy({ urlsBySample[$0] != nil }) {
      return coverage.alignedCoverage(poses: poses, rejectedIDs: rejectedIDs)
    }
    return .invalid
  }

  func makePhotogrammetryInput() throws -> BodyPhotogrammetryInput {
    guard !samples.isEmpty else { throw BodyCaptureArchiveError.empty }
    guard hasDistinctSamples else { throw BodyCaptureArchiveError.invalidSamples }
    return BodyPhotogrammetryInput(samples: samples)
  }
}

struct BodyPhotogrammetryInput: @unchecked Sendable {
  let samples: AnySequence<PhotogrammetrySample>
  private let reader: BodyPhotogrammetryReader

  fileprivate init(samples: [BodyCaptureStoredSample]) {
    let reader = BodyPhotogrammetryReader(samples: samples)
    self.reader = reader
    self.samples = reader.sequence
  }

  func validateReads() throws {
    try reader.throwIfFailed()
  }
}

private final class BodyPhotogrammetryReader {
  private let samples: [BodyCaptureStoredSample]
  private let lock = NSLock()
  private var firstError: Error?

  init(samples: [BodyCaptureStoredSample]) { self.samples = samples }

  var sequence: AnySequence<PhotogrammetrySample> {
    AnySequence { [self] in
      var index = 0
      return AnyIterator<PhotogrammetrySample> {
        guard index < samples.count else { return nil }
        defer { index += 1 }
        do {
          return try autoreleasepool { try load(samples[index]) }
        } catch {
          remember(error)
          return nil
        }
      }
    }
  }

  func throwIfFailed() throws {
    lock.lock()
    let error = firstError
    lock.unlock()
    if let error { throw error }
  }

  private func remember(_ error: Error) {
    lock.lock()
    if firstError == nil { firstError = error }
    lock.unlock()
  }

  private func load(_ stored: BodyCaptureStoredSample) throws -> PhotogrammetrySample {
    guard FileManager.default.fileExists(atPath: stored.imageURL.path) else {
      throw BodyCaptureArchiveError.missingFile(stored.imageURL)
    }
    guard let image = try? PhotogrammetrySample(contentsOf: stored.imageURL) else {
      throw BodyCaptureArchiveError.invalidImageFile(stored.imageURL)
    }
    let width = CVPixelBufferGetWidth(image.image), height = CVPixelBufferGetHeight(image.image)
    guard captureImageSource(at: stored.imageURL, type: .jpeg, width: width, height: height) != nil else {
      throw BodyCaptureArchiveError.invalidImageFile(stored.imageURL)
    }
    var sample = PhotogrammetrySample(id: stored.sampleID, image: image.image)
    sample.metadata = image.metadata
    sample.gravity = stored.gravity
    sample.depthDataMap = try BodyCaptureDepthPlane.read(from: stored.depthURL)
    sample.objectMask = try BodyCaptureMaskPlane.read(from: stored.maskURL, width: width, height: height)
    return sample
  }
}

enum BodyCaptureArchiveError: LocalizedError {
  case empty
  case invalidSamples
  case invalidDepth
  case invalidDepthFile(URL)
  case invalidMask
  case invalidMaskFile(URL)
  case invalidImageFile(URL)
  case missingFile(URL)
  case imageEncoding
  case occupiedSampleID
  case missingDirectory

  var errorDescription: String? {
    switch self {
    case .empty: "No body capture photos were saved."
    case .invalidSamples: "The saved capture contains conflicting sample records."
    case .invalidDepth: "The camera did not provide a usable depth map."
    case .invalidDepthFile: "A saved depth map is invalid."
    case .invalidMask: "The camera did not provide a usable subject mask."
    case .invalidMaskFile: "A saved subject mask is invalid."
    case .invalidImageFile: "A saved capture photo is invalid."
    case .missingFile: "A capture file is missing."
    case .imageEncoding: "The camera photo could not be encoded."
    case .occupiedSampleID: "A capture photo already uses this sample ID."
    case .missingDirectory: "The capture directory is no longer available."
    }
  }
}

enum BodyCaptureDepthPlane {
  static func rotateClockwise(_ values: [Float], width: Int, height: Int) -> [Float]? {
    guard width > 0, height > 0, width <= Int.max / height, values.count == width * height else { return nil }
    var result = [Float](repeating: 0, count: values.count)
    for y in 0..<height {
      for x in 0..<width {
        result[x * height + height - 1 - y] = values[y * width + x]
      }
    }
    return result
  }

  static func write(depth: CVPixelBuffer, confidence: CVPixelBuffer, mask: CVPixelBuffer, to url: URL) throws {
    let data = try encoded(depth: depth, confidence: confidence, mask: mask)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
    guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == data.count else {
      throw BodyCaptureArchiveError.invalidDepthFile(url)
    }
  }

  private static func encoded(depth: CVPixelBuffer, confidence: CVPixelBuffer, mask: CVPixelBuffer) throws -> Data {
    guard CVPixelBufferGetPixelFormatType(depth) == kCVPixelFormatType_DepthFloat32,
          CVPixelBufferGetPixelFormatType(confidence) == kCVPixelFormatType_OneComponent8,
          CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else {
      throw BodyCaptureArchiveError.invalidDepth
    }
    defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
    guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else {
      throw BodyCaptureArchiveError.invalidDepth
    }
    defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
    guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
          CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else {
      throw BodyCaptureArchiveError.invalidMask
    }
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

    let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
    let depthStride = CVPixelBufferGetBytesPerRow(depth)
    let confidenceWidth = CVPixelBufferGetWidth(confidence), confidenceHeight = CVPixelBufferGetHeight(confidence)
    let confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
    let maskWidth = CVPixelBufferGetWidth(mask), maskHeight = CVPixelBufferGetHeight(mask)
    let maskStride = CVPixelBufferGetBytesPerRow(mask)
    guard let portraitWidth = UInt32(exactly: height), let portraitHeight = UInt32(exactly: width),
          width > 0, height > 0, width <= (Int.max - 12) / 4 / height,
          depthStride.isMultiple(of: 4), width <= depthStride / 4,
          height <= CVPixelBufferGetDataSize(depth) / depthStride,
          confidenceWidth > 0, confidenceHeight > 0, confidenceStride >= confidenceWidth,
          confidenceHeight <= CVPixelBufferGetDataSize(confidence) / confidenceStride,
          let depthBase = CVPixelBufferGetBaseAddress(depth),
          let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else {
      throw BodyCaptureArchiveError.invalidDepth
    }
    guard maskWidth > 0, maskHeight > 0, maskStride >= maskWidth,
          maskHeight <= CVPixelBufferGetDataSize(mask) / maskStride,
          let maskBase = CVPixelBufferGetBaseAddress(mask) else { throw BodyCaptureArchiveError.invalidMask }

    var data = Data(count: 12 + width * height * 4)
    try data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
      guard let output = bytes.baseAddress else { throw BodyCaptureArchiveError.invalidDepth }
      store(0x31504442, at: 0, in: output) // BDP1
      store(portraitWidth, at: 4, in: output)
      store(portraitHeight, at: 8, in: output)
      var hasDepth = false
      for y in 0..<height {
        let depthRow = depthBase.advanced(by: y * depthStride).assumingMemoryBound(to: Float.self)
        let confidenceY = scaledPixelCenter(y, from: height, to: confidenceHeight)
        let confidenceRow = confidenceBase.advanced(by: confidenceY * confidenceStride).assumingMemoryBound(to: UInt8.self)
        let portraitX = height - 1 - y
        let maskX = scaledPixelCenter(portraitX, from: height, to: maskWidth)
        for x in 0..<width {
          let meters = depthRow[x]
          guard meters.isFinite, meters > 0 else { continue }
          let confidenceX = scaledPixelCenter(x, from: width, to: confidenceWidth)
          let quality = confidenceRow[confidenceX]
          guard quality == 1 || quality == 2 else { continue }
          let maskY = scaledPixelCenter(x, from: width, to: maskHeight)
          guard maskBase.advanced(by: maskY * maskStride).assumingMemoryBound(to: UInt8.self)[maskX] >= 128 else { continue }
          store(meters.bitPattern, at: 12 + (x * height + portraitX) * 4, in: output)
          hasDepth = true
        }
      }
      guard hasDepth else { throw BodyCaptureArchiveError.invalidDepth }
    }
    return data
  }

  static func read(from url: URL) throws -> CVPixelBuffer {
    guard FileManager.default.fileExists(atPath: url.path) else { throw BodyCaptureArchiveError.missingFile(url) }
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let error = BodyCaptureArchiveError.invalidDepthFile(url)
    return try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
      guard bytes.count >= 12, word(at: 0, in: bytes) == 0x31504442 else { throw error }
      let width = Int(word(at: 4, in: bytes)), height = Int(word(at: 8, in: bytes))
      guard width > 0, height > 0, width <= (Int.max - 12) / 4 / height,
            bytes.count == 12 + width * height * 4 else { throw error }
      var output: CVPixelBuffer?
      guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32, nil, &output) == kCVReturnSuccess,
            let output, CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else { throw error }
      defer { CVPixelBufferUnlockBaseAddress(output, []) }
      let stride = CVPixelBufferGetBytesPerRow(output)
      guard stride.isMultiple(of: 4), width <= stride / 4, height <= CVPixelBufferGetDataSize(output) / stride,
            let base = CVPixelBufferGetBaseAddress(output) else { throw error }
      var hasDepth = false
      for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
        for x in 0..<width {
          let meters = Float(bitPattern: word(at: 12 + (y * width + x) * 4, in: bytes))
          guard meters.isFinite, meters >= 0 else { throw error }
          row[x] = meters
          if meters > 0 { hasDepth = true }
        }
      }
      guard hasDepth else { throw error }
      return output
    }
  }

  private static func store(_ value: UInt32, at offset: Int, in output: UnsafeMutableRawPointer) {
    withUnsafeBytes(of: value.littleEndian) {
      output.advanced(by: offset).copyMemory(from: $0.baseAddress!, byteCount: 4)
    }
  }

  private static func word(at offset: Int, in bytes: UnsafeRawBufferPointer) -> UInt32 {
    UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
  }
}

enum BodyCaptureMaskPlane {
  static func portrait(_ uprightMask: CVPixelBuffer, width: Int, height: Int,
                       context _: CIContext) throws -> CVPixelBuffer {
    let error = BodyCaptureArchiveError.invalidMask
    guard width > 0, height > 0, width <= Int.max / height,
          CVPixelBufferLockBaseAddress(uprightMask, .readOnly) == kCVReturnSuccess else { throw error }
    defer { CVPixelBufferUnlockBaseAddress(uprightMask, .readOnly) }
    guard let source = storage(uprightMask) else { throw error }
    if width == source.width && height == source.height { return uprightMask }
    let output = try allocate(width: width, height: height, error: error)
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    guard let target = storage(output) else { throw error }
    // Nearest-neighbor keeps the same pixel-center mapping as the depth mask lookup.
    let sourceColumns = (0..<width).map { scaledPixelCenter($0, from: width, to: source.width) }
    for y in 0..<height {
      let sourceY = scaledPixelCenter(y, from: height, to: source.height)
      let sourceRow = source.base.advanced(by: sourceY * source.stride)
      let targetRow = target.base.advanced(by: y * target.stride)
      for x in 0..<width { targetRow[x] = sourceRow[sourceColumns[x]] }
    }
    return output
  }

  static func read(from url: URL, width: Int, height: Int) throws -> CVPixelBuffer {
    let error = BodyCaptureArchiveError.invalidMaskFile(url)
    guard let source = captureImageSource(at: url, type: .png, width: width, height: height),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
          image.bitsPerComponent == 8, image.bitsPerPixel == 8, image.bytesPerRow >= width,
          image.alphaInfo == .none, let colorSpace = image.colorSpace,
          colorSpace.model == .monochrome else { throw error }
    let output = try allocate(width: width, height: height, error: error)
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    guard let context = bitmapContext(output, colorSpace: colorSpace) else { throw error }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return output
  }

  static func write(_ mask: CVPixelBuffer, to url: URL) throws {
    guard CVPixelBufferLockBaseAddress(mask, .readOnly) == kCVReturnSuccess else {
      throw BodyCaptureArchiveError.invalidMask
    }
    defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
    guard let context = bitmapContext(mask), let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw BodyCaptureArchiveError.invalidMask
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination),
          captureImageSource(at: url, type: .png, width: image.width, height: image.height) != nil else {
      throw BodyCaptureArchiveError.invalidMaskFile(url)
    }
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
  }

  private static func allocate(width: Int, height: Int, error: BodyCaptureArchiveError) throws -> CVPixelBuffer {
    var output: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &output) == kCVReturnSuccess,
          let output, CVPixelBufferLockBaseAddress(output, []) == kCVReturnSuccess else { throw error }
    return output
  }

  private static func bitmapContext(_ mask: CVPixelBuffer,
                                    colorSpace: CGColorSpace = CGColorSpaceCreateDeviceGray()) -> CGContext? {
    guard let plane = storage(mask) else { return nil }
    return CGContext(data: plane.base, width: plane.width, height: plane.height,
                     bitsPerComponent: 8, bytesPerRow: plane.stride, space: colorSpace,
                     bitmapInfo: CGImageAlphaInfo.none.rawValue)
  }

  private static func storage(_ mask: CVPixelBuffer) -> (base: UnsafeMutablePointer<UInt8>, width: Int, height: Int, stride: Int)? {
    let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
    let stride = CVPixelBufferGetBytesPerRow(mask)
    guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
          width > 0, height > 0, stride >= width, height <= CVPixelBufferGetDataSize(mask) / stride,
          let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
    return (base.assumingMemoryBound(to: UInt8.self), width, height, stride)
  }
}

private func scaledPixelCenter(_ index: Int, from source: Int, to target: Int) -> Int {
  min(target - 1, Int((Double(index) + 0.5) * Double(target) / Double(source)))
}

private func captureImageSource(at url: URL, type: UTType, width: Int, height: Int) -> CGImageSource? {
  guard width > 0, height > 0, width <= Int.max / height,
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        CGImageSourceGetType(source) == type.identifier as CFString,
        CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete,
        CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
        properties[kCGImagePropertyPixelWidth as String] as? Int == width,
        properties[kCGImagePropertyPixelHeight as String] as? Int == height,
        (properties[kCGImagePropertyOrientation as String] as? Int ?? 1) == 1 else { return nil }
  return source
}

struct BodyCapturePhotoWriter {
  private let directory: URL
  private let context = CIContext()
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter
  }()

  init(directory: URL) { self.directory = directory }

  func write(frame: ARFrame, sampleID: Int, azimuth: Double, fullBody: Bool,
             mask: CVPixelBuffer) throws -> BodyCaptureStoredSample {
    let files = FileManager.default
    var isDirectory: ObjCBool = false
    guard directory.isFileURL, files.fileExists(atPath: directory.path, isDirectory: &isDirectory),
          isDirectory.boolValue else { throw BodyCaptureArchiveError.missingDirectory }
    guard sampleID >= 0, sampleID < Int.max, azimuth.isFinite else {
      throw BodyCaptureArchiveError.invalidSamples
    }
    guard let sceneDepth = frame.sceneDepth, let confidence = sceneDepth.confidenceMap else {
      throw BodyCaptureArchiveError.invalidDepth
    }
    let camera = frame.camera
    let axes = camera.transform.columns
    let gravity = CMAcceleration(x: Double(-axes.1.y), y: Double(axes.0.y), z: Double(-axes.2.y))
    guard gravity.x.isFinite, gravity.y.isFinite, gravity.z.isFinite else {
      throw BodyCaptureArchiveError.invalidSamples
    }

    let basename = String(format: "body-%04lld", Int64(sampleID))
    let imageURL = directory.appendingPathComponent("\(basename).jpg")
    let depthURL = directory.appendingPathComponent("\(basename).depth")
    let maskURL = directory.appendingPathComponent("\(basename).png")
    let destinations = [depthURL, maskURL, imageURL]
    guard destinations.allSatisfy({ !files.fileExists(atPath: $0.path) }) else {
      throw BodyCaptureArchiveError.occupiedSampleID
    }
    let staging = directory.appendingPathComponent(".sample-\(UUID().uuidString)", isDirectory: true)
    let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
    try files.createDirectory(at: staging, withIntermediateDirectories: false, attributes: protection)
    var published = 0
    defer {
      if published != destinations.count {
        for url in destinations.prefix(published).reversed() { try? files.removeItem(at: url) }
      }
      try? files.removeItem(at: staging)
    }
    let temporaryDepth = staging.appendingPathComponent(depthURL.lastPathComponent)
    let temporaryMask = staging.appendingPathComponent(maskURL.lastPathComponent)
    let temporaryImage = staging.appendingPathComponent(imageURL.lastPathComponent)
    try BodyCaptureDepthPlane.write(depth: sceneDepth.depthMap, confidence: confidence, mask: mask, to: temporaryDepth)

    let cgImage = try Self.portrait(frame.capturedImage, context: context)
    let portraitMask = try BodyCaptureMaskPlane.portrait(mask, width: cgImage.width, height: cgImage.height, context: context)
    try BodyCaptureMaskPlane.write(portraitMask, to: temporaryMask)
    guard let destination = CGImageDestinationCreateWithURL(temporaryImage as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw BodyCaptureArchiveError.imageEncoding
    }
    let dateString = Self.dateFormatter.string(from: Date())
    let metadata: [String: Any] = [
      kCGImageDestinationLossyCompressionQuality as String: 0.95,
      kCGImagePropertyOrientation as String: 1,
      kCGImagePropertyTIFFDictionary as String: [
        kCGImagePropertyTIFFOrientation as String: 1,
        kCGImagePropertyTIFFDateTime as String: dateString
      ],
      kCGImagePropertyExifDictionary as String: [
        kCGImagePropertyExifDateTimeOriginal as String: dateString,
        kCGImagePropertyExifDateTimeDigitized as String: dateString,
        kCGImagePropertyExifExposureTime as String: camera.exposureDuration,
        kCGImagePropertyExifExposureBiasValue as String: camera.exposureOffset,
        kCGImagePropertyExifPixelXDimension as String: cgImage.width,
        kCGImagePropertyExifPixelYDimension as String: cgImage.height
      ]
    ]
    CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
    guard CGImageDestinationFinalize(destination),
          captureImageSource(at: temporaryImage, type: .jpeg, width: cgImage.width, height: cgImage.height) != nil else {
      throw BodyCaptureArchiveError.imageEncoding
    }
    try files.setAttributes(protection, ofItemAtPath: temporaryImage.path)

    // The RGB file is published last; only a fully published sample reaches the archive.
    for (temporary, final) in zip([temporaryDepth, temporaryMask, temporaryImage], destinations) {
      try files.moveItem(at: temporary, to: final)
      published += 1
    }
    return BodyCaptureStoredSample(sampleID: sampleID, imageURL: imageURL, depthURL: depthURL, maskURL: maskURL,
                                   azimuth: azimuth, fullBody: fullBody, gravity: gravity)
  }

  static func portrait(_ nativeImage: CVPixelBuffer, context: CIContext) throws -> CGImage {
    let width = CVPixelBufferGetHeight(nativeImage), height = CVPixelBufferGetWidth(nativeImage)
    let portrait = CIImage(cvPixelBuffer: nativeImage).oriented(.right)
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    guard width > 0, height > 0, portrait.extent == bounds,
          let image = context.createCGImage(portrait, from: bounds) else {
      throw BodyCaptureArchiveError.imageEncoding
    }
    return image
  }
}
