import SceneKit
import Metal
import ModelIO
import simd

enum ScannedAvatarGeometry {
  static func load(url: URL, referenceHeightCM: Double? = nil) throws -> (node: SCNNode, calibration: AvatarScanCalibration) {
    let scene = try SCNScene(url: url, options: [.checkConsistency: true, .convertToYUp: true, .convertUnitsToMeters: 1.0])
    let root = scene.rootNode.clone()
    var hasTexture = false
    var geometryCount = 0
    root.enumerateChildNodes { node, _ in
      node.camera = nil
      node.light = nil
      if let geometry = node.geometry {
        geometryCount += 1
        for material in geometry.materials {
          if let contents = material.diffuse.contents,
             contents is UIImage || contents is URL || contents is String || contents is MDLTexture
              || contents is MTLTexture || type(of: contents) == CGImage.self {
            hasTexture = true
          }
          // Capture textures already contain lighting; preserve their photographed colors.
          material.lightingModel = .constant
        }
      }
    }
    guard geometryCount > 0, hasTexture else { throw AvatarScanError.invalidModel }
    let bounds = root.boundingBox
    let minimum = SIMD3(bounds.min.x, bounds.min.y, bounds.min.z)
    let maximum = SIMD3(bounds.max.x, bounds.max.y, bounds.max.z)
    let calibration = AvatarScanCalibration(minimum: minimum, maximum: maximum, referenceHeightCM: referenceHeightCM ?? Double(maximum.y - minimum.y) * 100, usesDepthScale: referenceHeightCM == nil)
    try calibration.validate()
    let center = (minimum + maximum) / 2
    root.position = SCNVector3(-center.x * calibration.scale, -minimum.y * calibration.scale, -center.z * calibration.scale)
    root.scale = SCNVector3(calibration.scale, calibration.scale, calibration.scale)
    return (root, calibration)
  }
}
