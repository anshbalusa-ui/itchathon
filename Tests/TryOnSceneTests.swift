import Metal
import SceneKit
import UIKit
import XCTest
@testable import FitCheck

#if DEBUG
final class TryOnSceneTests: XCTestCase {
  @MainActor
  func testUInt32GarmentBeyondOldVertexLimitRendersBothMaterialSides() throws {
    let columns = 200, rows = 200, panelCount = (columns+1)*(rows+1)
    var positions: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = []
    positions.reserveCapacity(panelCount*2); uv.reserveCapacity(panelCount*2)
    for side in 0..<2 {
      for y in 0...rows { for x in 0...columns {
        let u = Float(x)/Float(columns), v = Float(y)/Float(rows)
        positions.append(SIMD3(u-0.5,0.5-v,side == 0 ? 0.015 : -0.015))
        uv.append(SIMD2(u,v))
      } }
    }
    var front: [UInt32] = [], back: [UInt32] = []
    for y in 0..<rows { for x in 0..<columns {
      let a = UInt32(y*(columns+1)+x), b = a+1, c = a+UInt32(columns+1), d = c+1
      front += [a,c,b,b,c,d]
      let offset = UInt32(panelCount)
      back += [b+offset,c+offset,a+offset,d+offset,c+offset,b+offset]
    } }
    let url = try XCTUnwrap(Bundle.main.url(forResource: "synthetic-shirt",withExtension: "png",subdirectory: "OnYouTryOnFixtures"))
    let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url))?.cgImage)
    let prepared = try TryOnPreparedGarment(mesh: TryOnMesh(positions: positions,textureCoordinates: uv,front: front,back: back),
      front: image,backColor: SIMD3(0.07,0.50,0.56))
    let coordinator = BodySceneView.Coordinator()
    let scene = coordinator.scene, camera = coordinator.camera
    scene.rootNode.addChildNode(prepared.makeNode())
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
    renderer.scene = scene; renderer.pointOfView = camera
    for z: Float in [2,-2] {
      // Explicit orthogonal poses avoid look(at:)'s antiparallel singularity.
      camera.position = SCNVector3(0,0,z)
      camera.eulerAngles = SCNVector3(0,z > 0 ? Float(0) : Float.pi,0)
      let frame = renderer.snapshot(atTime: 0,with: CGSize(width: 180,height: 220),antialiasingMode: .none)
      let evidence = XCTAttachment(image: frame)
      evidence.name = z > 0 ? "large-index-front" : "large-index-back"
      evidence.lifetime = .keepAlways; add(evidence)
      XCTAssertGreaterThan(try clothPixels(frame),200,"A high UInt32 index must not silently omit the garment")
    }
  }

  @MainActor
  func testPreparedGarmentRejectsDamagedIndicesNonfiniteVerticesUVsAndDegenerateFaces() throws {
    let positions = (0..<100).map { SIMD3<Float>(Float($0 % 10)*0.01,Float($0/10)*0.01,0) }
    let uv = Array(repeating: SIMD2<Float>(0.5,0.5),count: positions.count)
    let good = TryOnMesh(positions: positions,textureCoordinates: uv,front: [0,1,10],back: [10,1,0])
    let url = try XCTUnwrap(Bundle.main.url(forResource: "synthetic-shirt",withExtension: "png",subdirectory: "OnYouTryOnFixtures"))
    let image = try XCTUnwrap(UIImage(data: Data(contentsOf: url))?.cgImage)
    var index = good; index.front[1] = 100
    var vertex = good; vertex.positions[0].x = .infinity
    var texture = good; texture.textureCoordinates[0].y = 1.5
    var degenerate = good; degenerate.front = [0,0,0]
    for bad in [index,vertex,texture,degenerate] {
      XCTAssertThrowsError(try TryOnPreparedGarment(mesh: bad,front: image,backColor: SIMD3(repeating: 0.4)))
    }
  }

  private func clothPixels(_ image: UIImage) throws -> Int {
    let cg = try XCTUnwrap(image.cgImage)
    var pixels = [UInt8](repeating: 0,count: cg.width*cg.height*4)
    try pixels.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(CGContext(data: bytes.baseAddress,width: cg.width,height: cg.height,
        bitsPerComponent: 8,bytesPerRow: cg.width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(cg,in: CGRect(x: 0,y: 0,width: cg.width,height: cg.height))
    }
    var count = 0
    for i in stride(from: 0,to: pixels.count,by: 4) {
      if Int(pixels[i+1]) > Int(pixels[i])+25 && Int(pixels[i+2]) > Int(pixels[i])+20 && pixels[i+1] > 45 { count += 1 }
    }
    return count
  }
}
#endif
