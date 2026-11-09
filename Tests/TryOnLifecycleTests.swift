import UIKit
import XCTest
@testable import FitCheck

#if DEBUG
@MainActor
final class TryOnLifecycleTests: XCTestCase {
  func testCancelledOlderLoadCannotReplaceNewGarmentGeometry() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let avatar = try XCTUnwrap(fixture.scans.asset)
    let tide = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let coral = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Coral") })
    let model = TryOnModel()
    let old = Task { await model.load(avatar: avatar,garment: tide,photoURL: fixture.closet.imageURL(for: tide)) }
    await Task.yield()
    model.cancel()
    let next = Task { await model.load(avatar: avatar,garment: coral,photoURL: fixture.closet.imageURL(for: coral)) }
    await old.value; await next.value
    let shown = try XCTUnwrap(model.result)
    let expected = try await TryOnBuilder().build(avatar: avatar,garment: coral,photoURL: fixture.closet.imageURL(for: coral)) { _ in }
    XCTAssertEqual(shown.shape.mesh.positions,expected.shape.mesh.positions)
    XCTAssertNil(model.failure)
    model.cancel()
    XCTAssertNil(model.result)
    XCTAssertEqual(try AvatarScanStore.digest(avatar.url),avatar.record.sha256)
  }

  func testFailedPhotoCanBeRetakenAndRetriedWithoutChangingSavedAvatar() async throws {
    let fixture = try OnYouTryOnFixtures.make(scenario: "missing-photo")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let avatar = try XCTUnwrap(fixture.scans.asset)
    let old = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let model = TryOnModel()
    await model.load(avatar: avatar,garment: old,photoURL: fixture.closet.imageURL(for: old))
    XCTAssertNil(model.result)
    XCTAssertNotNil(model.failure)
    let url = try XCTUnwrap(Bundle.main.url(forResource: "synthetic-shirt",withExtension: "png",subdirectory: "OnYouTryOnFixtures"))
    let data = try Data(contentsOf: url)
    let capture = GarmentCaptureResult(image: data,dimensions: try XCTUnwrap(old.dimensions),pattern: old.pattern)
    try fixture.closet.replaceCapture(for: old,with: capture)
    let replacement = try XCTUnwrap(fixture.closet.garments.first { $0.id == old.id })
    XCTAssertNotEqual(replacement.imageID,old.imageID)
    await model.load(avatar: avatar,garment: replacement,photoURL: fixture.closet.imageURL(for: replacement))
    let recovered = try XCTUnwrap(model.result)
    XCTAssertTrue(recovered.shape.mesh.positions.contains { abs($0.x) > 0.2 && $0.y > 1.1 })
    XCTAssertNil(model.failure)
    XCTAssertEqual(try AvatarScanStore.digest(avatar.url),avatar.record.sha256)
    XCTAssertEqual(fixture.scans.asset?.record,avatar.record)
  }

  func testLegacyCartoonWithoutCapturedObservationsCannotBecomeSuccessfulShirt() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let avatar = try XCTUnwrap(fixture.scans.asset)
    let original = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let data = try Data(contentsOf: fixture.closet.imageURL(for: original))
    let legacy = try fixture.closet.add(name: "Synthetic unrecognized legacy photo",image: data,
      dimensions: original.dimensions,productURL: nil)
    do {
      _ = try await TryOnBuilder().build(avatar: avatar,garment: legacy,photoURL: fixture.closet.imageURL(for: legacy)) { _ in }
      XCTFail("An authored cartoon is not evidence of native garment recognition")
    } catch let error as TryOnError {
      guard case .shirt = error else { return XCTFail("Expected actual landmark rejection, got \(error)") }
    }
    XCTAssertEqual(try AvatarScanStore.digest(avatar.url),avatar.record.sha256)
  }

  func testCapturedPatternIsBoundToExactImageAndRejectedAfterSubstitution() throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let tide = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let coral = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Coral") })
    let tidePhoto = try Data(contentsOf: fixture.closet.imageURL(for: tide))
    let coralPhoto = try Data(contentsOf: fixture.closet.imageURL(for: coral))
    let evidence = try XCTUnwrap(tide.pattern)
    XCTAssertTrue(evidence.matches(tidePhoto))
    XCTAssertFalse(evidence.matches(coralPhoto))
    let oldImageID = tide.imageID
    XCTAssertThrowsError(try fixture.closet.replaceCapture(for: tide,with:
      GarmentCaptureResult(image: coralPhoto,dimensions: try XCTUnwrap(tide.dimensions),pattern: evidence)))
    XCTAssertEqual(fixture.closet.garments.first { $0.id == tide.id }?.imageID,oldImageID)
    XCTAssertEqual(try Data(contentsOf: fixture.closet.imageURL(for: tide)),tidePhoto)
    let reopened = ClosetStore(directory: fixture.root.appendingPathComponent("closet"))
    XCTAssertEqual(reopened.garments.first { $0.id == tide.id }?.pattern,evidence)
  }
}
#endif
