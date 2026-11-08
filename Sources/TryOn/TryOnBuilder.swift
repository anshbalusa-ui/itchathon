@preconcurrency import SceneKit
import UIKit
import Vision

struct TryOnResult: Sendable, Identifiable {
  var id = UUID()
  var shape: TryOnShape
  var bodyYaw: Float
  var backColor: SIMD3<Float>
  var photoURL: URL
}

actor TryOnBuilder {
  func build(avatar: AvatarScanAsset, dimensions: GarmentScanDimensions, photoURL: URL,
             progress: @Sendable (String) async -> Void) async throws -> TryOnResult {
    try Task.checkCancellation()
    await progress("Opening your scans…")
    let loaded = try ScannedAvatarGeometry.load(url: avatar.url, referenceHeightCM: avatar.record.referenceHeightCM)
    let body = loaded.node
    let scene = SCNScene()
    scene.background.contents = UIColor.white
    scene.rootNode.addChildNode(body)
    let height = avatar.record.heightM
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.usesOrthographicProjection = true
    camera.camera?.orthographicScale = Double(height) * 0.56
    camera.camera?.zNear = 0.01
    camera.camera?.zFar = 20
    camera.position = SCNVector3(0,height / 2,height * 2)
    camera.look(at: SCNVector3(0,height / 2,0))
    scene.rootNode.addChildNode(camera)
    let renderer = SCNRenderer(device: nil, options: nil)
    renderer.scene = scene
    renderer.pointOfView = camera
    let size = CGSize(width: 480, height: 720)
    await progress("Finding your shoulders and arms…")
    var best: (score: Float, yaw: Float, points: [VNHumanBodyPoseObservation.JointName: CGPoint])?
    let joints: [VNHumanBodyPoseObservation.JointName] = [.neck,.leftShoulder,.rightShoulder,.leftElbow,.rightElbow,.leftHip,.rightHip]
    for index in 0..<8 {
      try Task.checkCancellation()
      let yaw = Float(index) * .pi / 4
      body.eulerAngles.y = yaw
      let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
      guard let cg = image.cgImage else { throw TryOnError.body }
      let request = VNDetectHumanBodyPoseRequest()
      let faces = VNDetectFaceRectanglesRequest()
      try VNImageRequestHandler(cgImage: cg).perform([request,faces])
      guard let observation = request.results?.first else { continue }
      var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
      var confidence: Float = 1
      for joint in joints {
        if let point = try? observation.recognizedPoint(joint), point.confidence >= 0.25 {
          points[joint] = point.location
          confidence = min(confidence, point.confidence)
        }
      }
      guard points.count == joints.count, let left = points[.leftShoulder], let right = points[.rightShoulder],
            left.x > right.x, let face = faces.results?.max(by: { $0.confidence < $1.confidence }) else { continue }
      let score = Float(left.x - right.x) * confidence * face.confidence
      if best == nil || score > best!.score { best = (score,yaw,points) }
    }
    guard let best else { throw TryOnError.pose }
    body.eulerAngles.y = best.yaw
    let surface = try Self.surface(body)
    let origin = renderer.projectPoint(SCNVector3(0,0,0))
    let unitX = renderer.projectPoint(SCNVector3(1,0,0))
    let unitY = renderer.projectPoint(SCNVector3(0,1,0))
    guard abs(unitX.x - origin.x) > 1, abs(unitY.y - origin.y) > 1 else { throw TryOnError.pose }
    func joint(_ name: VNHumanBodyPoseObservation.JointName) throws -> SIMD3<Float> {
      guard let point = best.points[name] else { throw TryOnError.pose }
      let px = Float(point.x * size.width)
      let py = Float((unitY.y > origin.y ? point.y : 1 - point.y) * size.height)
      let x = (px - origin.x) / (unitX.x - origin.x)
      let y = (py - origin.y) / (unitY.y - origin.y)
      for offset in [Float(0), -0.005, 0.005, -0.01, 0.01] {
        if let depth = surface.depth(x: x, y: y + offset) {
          return SIMD3(x, y + offset, (depth.front + depth.back) / 2)
        }
      }
      throw TryOnError.pose
    }
    let pose = TryOnBodyPose(neck: try joint(.neck), leftShoulder: try joint(.leftShoulder), rightShoulder: try joint(.rightShoulder),
                             leftElbow: try joint(.leftElbow), rightElbow: try joint(.rightElbow),
                             hips: (try joint(.leftHip) + joint(.rightHip)) / 2)
    try Task.checkCancellation()
    await progress("Reading your shirt’s shape…")
    let image = try GarmentImageProcessor.normalized(Data(contentsOf: photoURL))
    let landmarks = try GarmentLandmarkDetector().detect(in: image).map { SIMD2(Float($0.x),Float($0.y)) }
    let pattern = try Self.pattern(image, landmarks: landmarks)
    await progress("Shaping the shirt around your scan…")
    try Task.checkCancellation()
    let shape = try TryOnGeometry.build(surface: surface, pose: pose, pattern: pattern, dimensions: dimensions)
    try Task.checkCancellation()
    return TryOnResult(shape: shape, bodyYaw: best.yaw, backColor: pattern.color, photoURL: photoURL)
  }

  private static func surface(_ root: SCNNode) throws -> TryOnSurface {
    var triangles: [TryOnTriangle] = []
    var invalid = false
    root.enumerateChildNodes { node, stop in
      guard let geometry = node.geometry else { return }
      guard let source = geometry.sources(for: .vertex).first,
            source.usesFloatComponents, source.componentsPerVector >= 3,
            [4,8].contains(source.bytesPerComponent), source.vectorCount <= 250_000 else { invalid = true; stop.pointee = true; return }
      let vertices: [SIMD3<Float>] = source.data.withUnsafeBytes { bytes in
        (0..<source.vectorCount).map { index in
          func component(_ n: Int) -> Float {
            let offset = source.dataOffset + index * source.dataStride + n * source.bytesPerComponent
            guard offset >= 0, offset + source.bytesPerComponent <= bytes.count else { invalid = true; return .nan }
            return source.bytesPerComponent == 4 ? bytes.loadUnaligned(fromByteOffset: offset, as: Float.self)
              : Float(bytes.loadUnaligned(fromByteOffset: offset, as: Double.self))
          }
          return node.simdConvertPosition(SIMD3(component(0),component(1),component(2)), to: nil)
        }
      }
      guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { invalid = true; return }
      for element in geometry.elements {
        guard element.primitiveType == .triangles, [2,4].contains(element.bytesPerIndex),
              element.primitiveCount <= 500_000,
              element.data.count >= element.primitiveCount * 3 * element.bytesPerIndex else { invalid = true; continue }
        element.data.withUnsafeBytes { bytes in
          func index(_ i: Int) -> Int {
            let offset = i * element.bytesPerIndex
            return element.bytesPerIndex == 2 ? Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
              : Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
          }
          for i in 0..<element.primitiveCount {
            let a = index(i*3), b = index(i*3+1), c = index(i*3+2)
            guard a < vertices.count, b < vertices.count, c < vertices.count else { invalid = true; continue }
            triangles.append(TryOnTriangle(a: vertices[a],b: vertices[b],c: vertices[c]))
          }
        }
      }
    }
    guard !invalid, triangles.count >= 100, triangles.count <= 500_000 else { throw TryOnError.body }
    return TryOnSurface(triangles: triangles)
  }

  private static func pattern(_ image: CGImage, landmarks: [SIMD2<Float>]) throws -> TryOnPattern {
    let width = image.width, height = image.height
    guard width > 1, height > 1, width <= 1600, height <= 1600 else { throw TryOnError.shirt }
    var pixels = [UInt8](repeating: 0, count: width*height*4)
    let valid = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0,y: 0,width: width,height: height))
      return true
    }
    guard valid else { throw TryOnError.shirt }
    var alpha: [UInt8] = [], colors: [SIMD3<Float>] = []
    for i in 0..<(width*height) {
      alpha.append(pixels[i*4+3])
      if i % 53 == 0 && pixels[i*4+3] > 240 {
        colors.append(SIMD3(Float(pixels[i*4]),Float(pixels[i*4+1]),Float(pixels[i*4+2])) / 255)
      }
    }
    guard colors.count >= 20 else { throw TryOnError.shirt }
    let color = SIMD3((colors.map(\.x).sorted())[colors.count/2],(colors.map(\.y).sorted())[colors.count/2],(colors.map(\.z).sorted())[colors.count/2])
    return TryOnPattern(width: width,height: height,alpha: alpha,points: landmarks,color: color)
  }
}
