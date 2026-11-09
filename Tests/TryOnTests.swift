import Metal
import SceneKit
import UIKit
import XCTest
@testable import FitCheck

#if DEBUG
final class TryOnTests: XCTestCase {
  @MainActor
  func testSavedAvatarAndAdmittedShirtRenderInSameSceneAndStayAttached() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let asset = try XCTUnwrap(fixture.scans.asset)
    let garment = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let result = try await TryOnBuilder().build(avatar: asset, garment: garment, photoURL: fixture.closet.imageURL(for: garment)) { _ in }
    XCTAssertTrue(result.timings.usedCapturedLandmarks)
    XCTAssertTrue(result.shape.mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    let coordinator = BodySceneView.Coordinator()
    coordinator.updateScan(ScannedBodySource(url: asset.url,scene: result.avatar))
    coordinator.updateTryOn(result, showing: true)
    let node = try XCTUnwrap(coordinator.garmentNode)
    XCTAssertTrue(node.parent === coordinator.scene.rootNode)
    let geometry = try XCTUnwrap(node.geometry)
    XCTAssertEqual(geometry.sources(for: .normal).first?.vectorCount, result.shape.mesh.positions.count)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = coordinator.scene; renderer.pointOfView = coordinator.camera
    for (name, angle) in [("front", Float(0)), ("quarter", .pi / 4), ("right-side", .pi / 2), ("left-side", -.pi / 2), ("back", .pi)] {
      coordinator.positionCamera(angle: angle, height: asset.record.heightM)
      let visible = renderer.snapshot(atTime: 0, with: CGSize(width: 480, height: 720), antialiasingMode: .none)
      let visiblePixels = try Self.shirtPixels(visible)
      coordinator.updateTryOn(result, showing: false)
      let hidden = renderer.snapshot(atTime: 0, with: CGSize(width: 480, height: 720), antialiasingMode: .none)
      let hiddenPixels = try Self.shirtPixels(hidden)
      XCTAssertGreaterThan(visiblePixels - hiddenPixels, 250, "Actual cloth must be visible from \(name)")
      XCTAssertTrue(coordinator.garmentNode === node, "Visibility must not rebuild/reload or replace the attached node")
      coordinator.updateTryOn(result, showing: true)
      let attachment = XCTAttachment(image: visible); attachment.name = "onyou-tryon-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
    }
    coordinator.detach()
    XCTAssertNil(node.parent)
    XCTAssertNil(coordinator.garmentNode)
    XCTAssertNil(coordinator.scannedNode)
  }

  @MainActor
  func testTwoBodiesAndGarmentsProduceDifferentRealGeometryAndBoundedWarmCaches() async throws {
    let a = try OnYouTryOnFixtures.make(), b = try OnYouTryOnFixtures.make(body: "b")
    defer { try? FileManager.default.removeItem(at: a.root); try? FileManager.default.removeItem(at: b.root) }
    let first = try XCTUnwrap(a.closet.garments.first { $0.name.contains("Tide") })
    let second = try XCTUnwrap(a.closet.garments.first { $0.name.contains("Coral") })
    let actor = TryOnBuilder()
    let original = try await actor.build(avatar: XCTUnwrap(a.scans.asset), garment: first, photoURL: a.closet.imageURL(for: first)) { _ in }
    let warm = try await actor.build(avatar: XCTUnwrap(a.scans.asset), garment: first, photoURL: a.closet.imageURL(for: first)) { _ in }
    XCTAssertTrue(warm.timings.preparedSceneCacheHit)
    XCTAssertEqual(warm.shape.mesh.positions, original.shape.mesh.positions)
    let changedGarment = try await actor.build(avatar: XCTUnwrap(a.scans.asset), garment: second, photoURL: a.closet.imageURL(for: second)) { _ in }
    XCTAssertNotEqual(changedGarment.shape.mesh.positions, original.shape.mesh.positions)
    XCTAssertFalse(changedGarment.timings.patternCacheHit)
    let changedBody = try await actor.build(avatar: XCTUnwrap(b.scans.asset), garment: first, photoURL: a.closet.imageURL(for: first)) { _ in }
    XCTAssertNotEqual(changedBody.shape.mesh.positions, original.shape.mesh.positions)
    XCTAssertFalse(changedBody.timings.avatarCacheHit)
    let timing = XCTAttachment(data: try JSONEncoder().encode([
      "a_cold": original.timings, "a_warm": warm.timings,
      "a_second_shirt": changedGarment.timings, "b_first_shirt": changedBody.timings
    ]), uniformTypeIdentifier: "public.json")
    timing.name = "synthetic-production-contract-timings"; timing.lifetime = .keepAlways; add(timing)
  }

  @MainActor
  func testMissingPhotoScaleAndUnsupportedPoseFailWithoutChangingSavedAssets() async throws {
    for scenario in ["missing-photo", "photo-only", "unusable-pose"] {
      let fixture = try OnYouTryOnFixtures.make(scenario: scenario)
      defer { try? FileManager.default.removeItem(at: fixture.root) }
      let asset = try XCTUnwrap(fixture.scans.asset)
      let garment = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
      let digest = try AvatarScanStore.digest(asset.url)
      do {
        _ = try await TryOnBuilder().build(avatar: asset, garment: garment, photoURL: fixture.closet.imageURL(for: garment)) { _ in }
        XCTFail("Unsupported \(scenario) must not expose a ready scene")
      } catch let error as TryOnError {
        switch (scenario, error) {
        case ("missing-photo", .missingPhoto), ("photo-only", .missingDimensions), ("unusable-pose", .pose): break
        default: XCTFail("Wrong prerequisite failure: \(scenario) / \(error)")
        }
      }
      XCTAssertEqual(try AvatarScanStore.digest(asset.url), digest)
      XCTAssertEqual(AvatarScanStore(directory: asset.url.deletingLastPathComponent().deletingLastPathComponent()).asset?.record, asset.record)
    }
  }

  private static func shirtPixels(_ image: UIImage) throws -> Int {
    let cg = try XCTUnwrap(image.cgImage), width = cg.width, height = cg.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { raw in
      let context = try XCTUnwrap(CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var count = 0
    for i in stride(from: 0, to: bytes.count, by: 4) {
      let r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
      if g > r + 25 && b > r + 20 && g > 45 { count += 1 }
    }
    return count
  }
}
#endif
