import SceneKit
import UIKit
import XCTest
@testable import FitCheck

#if DEBUG
final class TryOnGeometryTests: XCTestCase {
  @MainActor
  func testObservedPoseIsStableUnderYawAndPreservesAnatomicalSides() throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let asset = try XCTUnwrap(fixture.scans.asset)
    let loaded = try ScannedAvatarGeometry.load(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
    let mesh = try TryOnSurface.extract(loaded.node)
    let original = try TryOnPoseEstimator.solve(mesh: mesh)
    XCTAssertGreaterThan(original.pose.leftShoulder.x, original.pose.neck.x)
    XCTAssertLessThan(original.pose.rightShoulder.x, original.pose.neck.x)
    XCTAssertGreaterThan(original.pose.leftElbow.x, original.pose.leftShoulder.x)
    XCTAssertLessThan(original.pose.rightElbow.x, original.pose.rightShoulder.x)
    for angle: Float in [0.73, .pi] {
      let cosine = cos(angle), sine = sin(angle)
      let rotated = mesh.points.map { SIMD3(cosine*$0.x+sine*$0.z, $0.y, -sine*$0.x+cosine*$0.z) }
      let solution = try TryOnPoseEstimator.solve(mesh: TryOnSourceMesh(points: rotated, triangles: mesh.triangles))
      XCTAssertLessThan(simd_distance(solution.pose.leftShoulder, original.pose.leftShoulder), 0.012)
      XCTAssertLessThan(simd_distance(solution.pose.rightShoulder, original.pose.rightShoulder), 0.012)
      XCTAssertLessThan(simd_distance(solution.pose.hips, original.pose.hips), 0.012)
      XCTAssertLessThan(simd_distance(solution.pose.neck, original.pose.neck), 0.012)
    }
  }

  @MainActor
  func testShirtHasValidPanelsAnchoredShouldersOpenNeckAndSurfaceClearance() async throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let asset = try XCTUnwrap(fixture.scans.asset)
    let shirt = try XCTUnwrap(fixture.closet.garments.first { $0.name.contains("Tide") })
    let result = try await TryOnBuilder().build(avatar: asset, garment: shirt, photoURL: fixture.closet.imageURL(for: shirt)) { _ in }
    let loaded = try ScannedAvatarGeometry.load(url: asset.url, referenceHeightCM: asset.record.referenceHeightCM)
    let solution = try TryOnPoseEstimator.solve(mesh: TryOnSurface.extract(loaded.node))
    let mesh = result.shape.mesh
    XCTAssertEqual(mesh.positions.count, mesh.textureCoordinates.count)
    for faces in [mesh.front,mesh.back] {
      XCTAssertEqual(faces.count % 3, 0)
      for i in stride(from: 0, to: faces.count, by: 3) {
        let indices = [Int(faces[i]),Int(faces[i+1]),Int(faces[i+2])]
        XCTAssertTrue(indices.allSatisfy { mesh.positions.indices.contains($0) })
        let a = mesh.positions[indices[0]], b = mesh.positions[indices[1]], c = mesh.positions[indices[2]]
        XCTAssertGreaterThan(simd_length_squared(simd_cross(b-a,c-a)), 1e-14)
      }
    }
    XCTAssertTrue(mesh.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
    XCTAssertTrue(mesh.textureCoordinates.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    func nearest(_ uv: CGPoint) -> SIMD3<Float> {
      let target = SIMD2<Float>(Float(uv.x),Float(uv.y))
      let index = mesh.textureCoordinates.indices.min { simd_distance_squared(mesh.textureCoordinates[$0],target) < simd_distance_squared(mesh.textureCoordinates[$1],target) }!
      return mesh.positions[index]
    }
    let photoLeftShoulder = nearest(OnYouTryOnFixtures.shirtPoints[6])
    let photoRightShoulder = nearest(OnYouTryOnFixtures.shirtPoints[24])
    XCTAssertLessThan(abs(photoLeftShoulder.x-solution.pose.rightShoulder.x), 0.06)
    XCTAssertLessThan(abs(photoRightShoulder.x-solution.pose.leftShoulder.x), 0.06)
    XCTAssertLessThan(abs(photoLeftShoulder.y-solution.pose.rightShoulder.y), 0.05)
    XCTAssertLessThan(abs(photoRightShoulder.y-solution.pose.leftShoulder.y), 0.05)
    let collar = nearest(OnYouTryOnFixtures.shirtPoints[0])
    XCTAssertLessThan(abs(collar.x-solution.pose.neck.x), 0.035)
    XCTAssertLessThan(collar.y, solution.pose.neck.y)
    XCTAssertGreaterThan(collar.y, solution.pose.neck.y-0.18)
    let leftCuff = nearest(OnYouTryOnFixtures.shirtPoints[9])
    let rightCuff = nearest(OnYouTryOnFixtures.shirtPoints[21])
    XCTAssertLessThan(leftCuff.x, solution.pose.rightShoulder.x)
    XCTAssertGreaterThan(rightCuff.x, solution.pose.leftShoulder.x)
    XCTAssertLessThan(leftCuff.y, photoLeftShoulder.y)
    XCTAssertLessThan(rightCuff.y, photoRightShoulder.y)
    // The sewn shell shares vertices across material boundaries. Every vertex
    // with observed body depth must remain outside one of its actual surfaces.
    for point in mesh.positions {
      if let depth = solution.surface.depth(x: point.x, y: point.y) {
        XCTAssertTrue(point.z >= depth.front+0.0058 || point.z <= depth.back-0.0058)
      }
    }
    let hem = nearest(OnYouTryOnFixtures.shirtPoints[15])
    XCTAssertEqual(solution.pose.neck.y-hem.y, Float(shirt.dimensions!.lengthM), accuracy: 0.025)
  }

  func testRootGeometryAndCompleteWorldTransformAreExtracted() throws {
    // Saved USDZs provide baked indexed geometry. SCNBox's lazy parametric
    // source can expose a unit cube; exercise the saved-mesh contract.
    let vertices = [-Float(0.2),0.2].flatMap { x in
      [-Float(0.9),0.9].flatMap { y in [-Float(0.1),0.1].map { SCNVector3(x,y,$0) } }
    }
    let indices: [UInt16] = [0,1,3,0,3,2,4,6,7,4,7,5,0,4,5,0,5,1,2,3,7,2,7,6,0,2,6,0,6,4,1,5,7,1,7,3]
    let geometry = SCNGeometry(sources: [.init(vertices: vertices)],elements: [SCNGeometryElement(indices: indices,primitiveType: .triangles)])
    let root = SCNNode(geometry: geometry)
    root.position = SCNVector3(0.3,0.9,-0.4)
    root.eulerAngles.y = .pi/2
    let mesh = try TryOnSurface.extract(root)
    let minimum = mesh.points.reduce(SIMD3(repeating: Float.greatestFiniteMagnitude),simd_min)
    let maximum = mesh.points.reduce(SIMD3(repeating: -Float.greatestFiniteMagnitude),simd_max)
    let diagnostic = XCTAttachment(string: "Synthetic root transform: \(root.simdTransform); extracted bounds: \(minimum), \(maximum)")
    diagnostic.name = "root-transform-diagnostic"; diagnostic.lifetime = .keepAlways; add(diagnostic)
    XCTAssertEqual(minimum.x, 0.2, accuracy: 0.001)
    XCTAssertEqual(maximum.x, 0.4, accuracy: 0.001)
    XCTAssertEqual(minimum.y, 0, accuracy: 0.001)
    XCTAssertEqual(maximum.y, 1.8, accuracy: 0.001)
    XCTAssertEqual(minimum.z, -0.6, accuracy: 0.001)
    XCTAssertEqual(maximum.z, -0.2, accuracy: 0.001)
    let parent = SCNNode(); parent.position.x = -0.5; parent.addChildNode(root)
    let nested = try TryOnSurface.extract(parent)
    XCTAssertEqual(nested.points.count,mesh.points.count)
    for i in mesh.points.indices { XCTAssertEqual(nested.points[i].x,mesh.points[i].x-0.5,accuracy: 0.001) }
  }

  @MainActor
  func testIndexedDepthMatchesExactUnindexedSectionsIncludingEdges() throws {
    let fixture = try OnYouTryOnFixtures.make()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let asset = try XCTUnwrap(fixture.scans.asset)
    let loaded = try ScannedAvatarGeometry.load(url: asset.url,referenceHeightCM: asset.record.referenceHeightCM)
    let solution = try TryOnPoseEstimator.solve(mesh: TryOnSurface.extract(loaded.node))
    for y: Float in [0.82,1.10,1.34,1.52] {
      let section = try XCTUnwrap(solution.surface.section(y))
      for indexed in section.components {
        var unindexed = indexed; unindexed.depthColumns = []
        for i in 0...37 {
          let x = indexed.minX+indexed.width*Float(i)/37
          let a = indexed.depth(at: x), b = unindexed.depth(at: x)
          XCTAssertEqual(a == nil,b == nil)
          if let a,let b {
            XCTAssertEqual(a.front,b.front,accuracy: 0.000001)
            XCTAssertEqual(a.back,b.back,accuracy: 0.000001)
          }
        }
        XCTAssertNil(indexed.depth(at: .nan))
      }
    }
  }

  func testGarmentEnvelopeDoesNotJumpAtHipMarkerOnUnchangedObservedContour() throws {
    // This constant concave prism reproduces a visible hem shelf: the old
    // raw-torso/convex-leg switch changed the radius despite unchanged input.
    let contour: [SIMD2<Float>] = [
      SIMD2(-0.2,-0.1),SIMD2(0.2,-0.1),SIMD2(0.2,0.1),SIMD2(0.08,0.1),
      SIMD2(0.04,0.04),SIMD2(-0.04,0.04),SIMD2(-0.08,0.1),SIMD2(-0.2,0.1)
    ]
    var points: [SIMD3<Float>] = [], triangles: [(Int,Int,Int)] = []
    for row in 0...8 { for point in contour { points.append(SIMD3(point.x,Float(row)*1.8/8,point.y)) } }
    for row in 0..<8 { for i in contour.indices {
      let a = row*contour.count+i, b = row*contour.count+(i+1)%contour.count
      triangles.append((a,b,a+contour.count)); triangles.append((b,b+contour.count,a+contour.count))
    } }
    let surface = try TryOnSurface(points: points,triangles: triangles)
    let above = try TryOnRing.make(segments: surface.garmentSection(at: 0.91,bridgeBelow: 0.9,halfWidth: 0.3),centerX: 0,shoulderWidth: 0.4,circumference: 1.2)
    let below = try TryOnRing.make(segments: surface.garmentSection(at: 0.89,bridgeBelow: 0.9,halfWidth: 0.3),centerX: 0,shoulderWidth: 0.4,circumference: 1.2)
    for (a,b) in zip(above.points,below.points) { XCTAssertLessThan(simd_distance(a,b),0.001) }
    // Convexity belongs to the clothing, never to the observed body's depth.
    XCTAssertEqual(try XCTUnwrap(surface.depth(x: 0,y: 0.91)).front,0.04,accuracy: 0.00001)
    XCTAssertEqual(try XCTUnwrap(surface.depth(x: 0,y: 0.89)).front,0.04,accuracy: 0.00001)
  }

  func testMalformedAndAdversarialSurfaceInputsRejectBeforeUnboundedIndexing() throws {
    let points = (0..<20).map { SIMD3<Float>(Float($0 % 3)*0.1,Float($0)*1.8/19,0) }
    let faces = Array(repeating: (0,19,5),count: 100)
    var damaged = faces; damaged[4] = (0,20,5)
    XCTAssertThrowsError(try TryOnSurface(points: points,triangles: damaged))
    var nonfinite = points; nonfinite[6].z = .nan
    XCTAssertThrowsError(try TryOnSurface(points: nonfinite,triangles: faces))
    // Every adversarial triangle spans the whole body height. The row index
    // must reject its bounded-entry overflow, rather than allocate 600 copies
    // of up to 500,000 triangle indices.
    XCTAssertThrowsError(try TryOnSurface(points: points,triangles: Array(repeating: (0,19,5),count: 8_000)))
    let surface = try TryOnSurface(points: points,triangles: faces)
    XCTAssertNil(surface.section(.nan))
    XCTAssertNil(surface.depth(x: 0,y: .infinity))
  }
}
#endif
