import SceneKit
import XCTest
@testable import FitCheck

@MainActor
final class BodySceneLifecycleTests: XCTestCase {
  func testRapidMeasurementChangesPublishOnlyLatestBodyAndDetachedSceneStaysEmpty() async throws {
    let coordinator = BodySceneView.Coordinator()
    let view = SCNView()
    coordinator.view = view
    coordinator.update(BodyMeasurements(height: 160, chest: 86, waist: 68, hips: 92, shoulders: 40))
    let old = coordinator.generationTask
    let latest = BodyMeasurements(height: 195, chest: 116, waist: 108, hips: 120, shoulders: 49)
    coordinator.update(latest)
    let current = coordinator.generationTask
    await old?.value
    await current?.value
    XCTAssertEqual(coordinator.measurements, latest)
    let geometry = try XCTUnwrap(coordinator.body.geometry)
    XCTAssertEqual(geometry.boundingBox.max.y - geometry.boundingBox.min.y, 1.95, accuracy: 0.002)
    XCTAssertFalse(coordinator.body.isHidden)
    XCTAssertFalse(coordinator.shorts.isHidden)
    XCTAssertTrue(view.accessibilityValue?.contains("195") == true)

    coordinator.update(.example)
    let pending = coordinator.generationTask
    coordinator.detach()
    await pending?.value
    XCTAssertTrue(coordinator.scene.rootNode.childNodes.isEmpty)
    XCTAssertEqual(coordinator.measurements, latest, "A dismissed request must not replace the last published body")
    XCTAssertNil(coordinator.view)
  }

  func testInvalidUpdateDoesNotDisplayOldBodyAsNewMeasurementsAndCanRecover() async throws {
    let coordinator = BodySceneView.Coordinator()
    let view = SCNView()
    coordinator.view = view
    coordinator.update(.example)
    await coordinator.generationTask?.value
    XCTAssertFalse(coordinator.body.isHidden)
    var invalid = BodyMeasurements.example
    invalid.waist = .nan
    coordinator.update(invalid)
    await coordinator.generationTask?.value
    XCTAssertNotNil(coordinator.failure)
    XCTAssertTrue(coordinator.body.isHidden)
    XCTAssertTrue(coordinator.shorts.isHidden)
    XCTAssertEqual(coordinator.measurements, .example)
    XCTAssertEqual(view.accessibilityValue, coordinator.failure)

    let recovered = BodyMeasurements(height: 185, chest: 104, waist: 90, hips: 108, shoulders: 46)
    coordinator.update(recovered)
    await coordinator.generationTask?.value
    XCTAssertNil(coordinator.failure)
    XCTAssertFalse(coordinator.body.isHidden)
    XCTAssertEqual(coordinator.measurements, recovered)
    XCTAssertEqual(try XCTUnwrap(coordinator.body.geometry).boundingBox.max.y, 1.85, accuracy: 0.002)
    coordinator.detach()
  }

  #if DEBUG
  func testSavedScanTakesPriorityOverPendingManualGeometry() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let asset = try XCTUnwrap(fixture.scans.asset)
    let prepared = try await PreparedAvatarScene.load(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
    let source = ScannedBodySource(url: asset.url, scene: prepared)
    let coordinator = BodySceneView.Coordinator()
    coordinator.update(.example)
    let pending = coordinator.generationTask
    coordinator.updateScan(source)
    let scanNode = try XCTUnwrap(coordinator.scannedNode)
    await pending?.value
    XCTAssertTrue(coordinator.scannedNode === scanNode)
    XCTAssertEqual(coordinator.loadedScan, source)
    XCTAssertTrue(coordinator.body.isHidden)
    XCTAssertTrue(coordinator.shorts.isHidden)
    XCTAssertNil(coordinator.measurements)
    XCTAssertEqual(try AvatarScanStore.digest(asset.url), asset.record.sha256)
    coordinator.detach()
  }
  #endif
}
