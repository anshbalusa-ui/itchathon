import SceneKit
import XCTest
@testable import FitCheck

final class AvatarScanTests: XCTestCase {
  func testScaleCalibrationRejectsInconsistentDepthAndInvalidBounds() throws {
    let valid = AvatarScanCalibration(minimum: SIMD3(-0.3, 0, -0.2), maximum: SIMD3(0.3, 1.78, 0.2), referenceHeightCM: 180)
    XCTAssertNoThrow(try valid.validate())
    XCTAssertEqual(valid.scale * valid.size.y, 1.8, accuracy: 0.0001)
    for height: Float in [0, .nan, .infinity, 1.0, 2.5] {
      var invalid = valid
      invalid.maximum.y = height
      XCTAssertThrowsError(try invalid.validate())
    }
    var wide = valid
    wide.maximum.x = 4
    XCTAssertThrowsError(try wide.validate())
  }

  func testDepthScaleDoesNotRequireOrChangeHeight() throws {
    let calibration = AvatarScanCalibration(minimum: SIMD3(-0.3, 0, -0.2), maximum: SIMD3(0.3, 1.82, 0.2), referenceHeightCM: 182, usesDepthScale: true)
    XCTAssertNoThrow(try calibration.validate())
    XCTAssertEqual(calibration.scale, 1, accuracy: 0.0001)
    var invalid = calibration
    invalid.referenceHeightCM = 170
    XCTAssertThrowsError(try invalid.validate())
  }

  @MainActor
  func testCoverageRequiresBothPassesAndEnoughImages() {
    XCTAssertFalse(BodyCaptureModel.hasCoverage(images: 59, passes: 2))
    XCTAssertFalse(BodyCaptureModel.hasCoverage(images: 100, passes: 1))
    XCTAssertTrue(BodyCaptureModel.hasCoverage(images: 60, passes: 2))
    let model = BodyCaptureModel()
    model.passCompleted(true)
    XCTAssertEqual(model.completedPasses, 0)
    model.cancel()
    XCTAssertEqual(model.phase, .setup)
    XCTAssertNil(model.modelURL)
    XCTAssertFalse(model.canFinish)
  }

  @MainActor
  func testTexturedGeometryPersistsAndCorruptionFailsClosed() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    // A textured box is a synthetic storage/coordinate fixture, not evidence of scanning a person.
    let scene = SCNScene()
    let box = SCNBox(width: 0.6, height: 1.8, length: 0.3, chamferRadius: 0)
    let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
      UIColor.brown.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    }
    let texture = root.appendingPathComponent("texture.png")
    try XCTUnwrap(image.pngData()).write(to: texture)
    box.firstMaterial?.diffuse.contents = texture
    let node = SCNNode(geometry: box)
    node.position.y = 0.9
    scene.rootNode.addChildNode(node)
    let input = root.appendingPathComponent("fixture.usdz")
    XCTAssertTrue(scene.write(to: input, options: nil, delegate: nil, progressHandler: nil))
    let loaded = try ScannedAvatarGeometry.load(url: input, referenceHeightCM: 180)
    XCTAssertEqual(loaded.calibration.size.y, 1.8, accuracy: 0.001)
    let automatic = try ScannedAvatarGeometry.load(url: input)
    XCTAssertTrue(automatic.calibration.usesDepthScale)
    XCTAssertEqual(automatic.calibration.scale, 1, accuracy: 0.0001)
    let repository = root.appendingPathComponent("Stored")
    let store = AvatarScanStore(directory: repository)
    try store.save(model: input, calibration: loaded.calibration, imageCount: 80, completedPasses: 2)
    let saved = try XCTUnwrap(store.asset)
    XCTAssertTrue(saved.record.isValid)
    XCTAssertEqual(AvatarScanStore(directory: repository).asset, saved)
    let automaticStore = AvatarScanStore(directory: root.appendingPathComponent("Automatic"))
    try automaticStore.save(model: input, calibration: automatic.calibration, imageCount: 80, completedPasses: 2)
    XCTAssertEqual(automaticStore.asset?.record.usesDepthScale, true)
    XCTAssertEqual(automaticStore.asset?.record.scale ?? 0, 1, accuracy: 0.0001)
    XCTAssertThrowsError(try store.save(model: input, calibration: loaded.calibration, imageCount: 10, completedPasses: 1))
    XCTAssertEqual(store.asset, saved)
    XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url.path))
    try Data("corrupt".utf8).write(to: saved.url)
    let reopened = AvatarScanStore(directory: repository)
    XCTAssertNil(reopened.asset)
    XCTAssertNotNil(reopened.error)
    XCTAssertTrue(reopened.hasUnreadableScan)
    XCTAssertTrue(FileManager.default.fileExists(atPath: saved.url.path))
    reopened.error = nil
    XCTAssertTrue(reopened.hasUnreadableScan)
    reopened.delete()
    XCTAssertNil(reopened.error)
    XCTAssertFalse(reopened.hasUnreadableScan)
    XCTAssertFalse(FileManager.default.fileExists(atPath: saved.url.path))
  }

  @MainActor
  func testDeletingScanLeavesMeasurementStorageAlone() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let name = "AvatarScanTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let measurements = OnYouStore(defaults: defaults)
    XCTAssertTrue(measurements.save(.example))
    let store = AvatarScanStore(directory: directory)
    store.delete()
    XCTAssertNil(store.error)
    XCTAssertEqual(OnYouStore(defaults: defaults).current, .example)
  }
}
