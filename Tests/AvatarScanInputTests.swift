import CoreVideo
import XCTest
@testable import FitCheck

final class AvatarScanInputTests: XCTestCase {
  func testPoseMappingAcceptsFilesystemAliasesWithoutCountingDuplicates() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("Images")
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
    // Empty files exercise path identity only, not reconstruction or depth accuracy.
    let urls = (0..<60).map { original.appendingPathComponent("\($0).heic") }
    for url in urls { try Data().write(to: url) }
    let aliased = Set((0..<60).map { alias.appendingPathComponent("\($0).heic") })
    let input = AvatarScanInput(imageURLs: aliased, depthImageURLs: aliased)
    var mapping = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ($0.offset, $0.element) })
    XCTAssertEqual(try input.validate(usedSampleIDs: Set(0..<60), urlsBySample: mapping, rejectedIDs: [], passes: 2), 60)
    mapping[59] = alias.appendingPathComponent("0.heic")
    XCTAssertThrowsError(try input.validate(usedSampleIDs: Set(0..<60), urlsBySample: mapping, rejectedIDs: [], passes: 2))
  }

  func testOnlySavedAlignedImagesWithRetainedDepthCount() throws {
    let urls = (0..<80).map { URL(fileURLWithPath: "/capture/\($0).heic") }
    let input = AvatarScanInput(imageURLs: Set(urls), depthImageURLs: Set(urls.prefix(40)))
    XCTAssertEqual(try input.validate(passes: 2), 80)
    let mapping = Dictionary(uniqueKeysWithValues: urls.enumerated().map { ($0.offset, $0.element) })
    let all = Set(mapping.keys)
    XCTAssertEqual(try input.validate(usedSampleIDs: all, urlsBySample: mapping, rejectedIDs: [], passes: 2), 80)
    XCTAssertEqual(try input.validate(usedSampleIDs: Set(0..<60), urlsBySample: mapping, rejectedIDs: [], passes: 2), 60)
    // Enough RGB images remain, but too many depth-bearing samples were rejected.
    XCTAssertThrowsError(try input.validate(usedSampleIDs: all, urlsBySample: mapping,
                                            rejectedIDs: Set(0..<20), passes: 2))
    XCTAssertThrowsError(try input.validate(usedSampleIDs: Set(0..<59), urlsBySample: mapping,
                                            rejectedIDs: [], passes: 2))
    XCTAssertThrowsError(try input.validate(usedSampleIDs: all, urlsBySample: mapping,
                                            rejectedIDs: [], passes: 1))
    var missing = mapping
    missing[79] = nil
    XCTAssertThrowsError(try input.validate(usedSampleIDs: all, urlsBySample: missing, rejectedIDs: [], passes: 2))
    var duplicate = mapping
    duplicate[79] = urls[0]
    XCTAssertThrowsError(try input.validate(usedSampleIDs: all, urlsBySample: duplicate, rejectedIDs: [], passes: 2))
    var unknown = mapping
    unknown[79] = URL(fileURLWithPath: "/different/79.heic")
    XCTAssertThrowsError(try input.validate(usedSampleIDs: all, urlsBySample: unknown, rejectedIDs: [], passes: 2))
  }

  func testMissingSavedPhotosAndMissingDepthCannotPassPreflight() {
    let urls = Set((0..<59).map { URL(fileURLWithPath: "/capture/\($0).heic") })
    XCTAssertThrowsError(try AvatarScanInput(imageURLs: urls, depthImageURLs: urls).validate(passes: 2))
    let more = urls.union([URL(fileURLWithPath: "/capture/59.heic")])
    XCTAssertThrowsError(try AvatarScanInput(imageURLs: more, depthImageURLs: []).validate(passes: 2))
    let remote = Set((0..<60).map { URL(string: "https://example.com/\($0).heic")! })
    XCTAssertThrowsError(try AvatarScanInput(imageURLs: remote, depthImageURLs: remote).validate(passes: 2))
  }

  func testDepthThresholdRoundsUpForAnOddAcceptedImageCount() {
    let urls = (0..<61).map { URL(fileURLWithPath: "/capture/\($0).heic") }
    XCTAssertThrowsError(try AvatarScanInput(imageURLs: Set(urls), depthImageURLs: Set(urls.prefix(30))).validate(passes: 2))
    XCTAssertNoThrow(try AvatarScanInput(imageURLs: Set(urls), depthImageURLs: Set(urls.prefix(31))).validate(passes: 2))
  }

  func testDepthPresenceRequiresPositiveFinitePixelsAndRespectsRowStride() throws {
    XCTAssertFalse(AvatarScanInput.containsFiniteDepth(nil))
    var color: CVPixelBuffer?
    XCTAssertEqual(CVPixelBufferCreate(nil, 7, 5, kCVPixelFormatType_32BGRA, nil, &color), kCVReturnSuccess)
    XCTAssertFalse(AvatarScanInput.containsFiniteDepth(color))
    for format in [kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_DisparityFloat32] {
      var optional: CVPixelBuffer?
      XCTAssertEqual(CVPixelBufferCreate(nil, 7, 5, format, nil, &optional), kCVReturnSuccess)
      let buffer = try XCTUnwrap(optional)
      for value: Float in [0, -1, .nan, .infinity, 1] {
        XCTAssertEqual(CVPixelBufferLockBaseAddress(buffer, []), kCVReturnSuccess)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<5 {
          let row = base.advanced(by: y * stride).assumingMemoryBound(to: Float.self)
          for x in 0..<7 { row[x] = 0 }
        }
        base.advanced(by: 4 * stride).assumingMemoryBound(to: Float.self)[6] = value
        CVPixelBufferUnlockBaseAddress(buffer, [])
        XCTAssertEqual(AvatarScanInput.containsFiniteDepth(buffer), value.isFinite && value > 0)
      }
    }
  }
}
