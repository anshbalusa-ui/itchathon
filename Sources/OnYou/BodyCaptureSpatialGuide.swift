import SceneKit
import UIKit

@MainActor
final class BodyCaptureSpatialGuide {
  var root = SCNNode()
  private var halo = SCNNode()
  private var marker = SCNNode(geometry: SCNSphere(radius: 0.016))
  private var target = SCNNode(geometry: SCNSphere(radius: 0.023))
  private var segments: [SCNNode] = []
  private(set) var capturedBins = Set<Int>()
  private var placed = false

  init() {
    root.name = "scan.spatial-guide"
    root.isHidden = true
    root.addChildNode(halo)
    for index in 0..<BodyCaptureGuideState.segmentCount {
      let step = Float.pi * 2 / Float(BodyCaptureGuideState.segmentCount)
      let start = Float(index) * step + step * 0.14
      let end = Float(index + 1) * step - step * 0.14
      let track = SCNNode(geometry: Self.arc(start: start, end: end))
      track.geometry?.materials = [Self.material(.white)]
      track.opacity = 0.22
      halo.addChildNode(track)
      let confirmed = SCNNode(geometry: Self.arc(start: start, end: end))
      confirmed.geometry?.materials = [Self.material(.systemYellow)]
      confirmed.position.z = 0.002
      confirmed.opacity = 0
      halo.addChildNode(confirmed)
      segments.append(confirmed)
    }
    let base = SCNNode(geometry: Self.arc(start: -.pi / 2, end: .pi / 2))
    base.geometry?.materials = [Self.material(.white)]
    base.eulerAngles.x = -.pi / 2
    base.scale = SCNVector3(0.74, 0.28, 1)
    base.position.y = -1.025
    base.opacity = 0.25
    halo.addChildNode(base)
    marker.geometry?.materials = [Self.material(.systemYellow)]
    target.geometry?.materials = [Self.material(.white)]
    halo.addChildNode(marker)
    halo.addChildNode(target)
  }

  func update(_ state: BodyCaptureGuideState?, now: TimeInterval, reduceMotion: Bool) {
    guard let state, state.isFresh(now: now) else {
      root.removeAllActions()
      root.opacity = 1
      root.isHidden = true
      return
    }
    SCNTransaction.begin()
    SCNTransaction.disableActions = true
    root.simdTransform = state.placement.transform
    halo.simdScale = SIMD3(state.placement.halfSize.x, state.placement.halfSize.y, state.placement.halfSize.x)
    root.isHidden = false
    if reduceMotion {
      root.removeAllActions()
      root.opacity = 1
    } else if !placed {
      root.opacity = 0
      root.runAction(.fadeIn(duration: 0.3))
    }
    for (index, node) in segments.enumerated() {
      let opacity: CGFloat = state.capturedBins.contains(index) ? 1 : 0
      if reduceMotion || !placed {
        node.removeAllActions()
        node.opacity = opacity
      } else if state.capturedBins.contains(index) != capturedBins.contains(index) {
        node.removeAllActions()
        let fade = SCNAction.fadeOpacity(to: opacity, duration: 0.25)
        fade.timingMode = .easeInEaseOut
        node.runAction(fade)
      }
    }
    marker.isHidden = state.yaw == nil || reduceMotion
    if let yaw = state.yaw, yaw.isFinite { marker.simdPosition = BodyCaptureGuideState.markerPosition(angle: yaw) }
    target.isHidden = state.neededAngle == nil
    if let angle = state.neededAngle, angle.isFinite {
      target.simdPosition = BodyCaptureGuideState.markerPosition(angle: angle)
    }
    capturedBins = state.capturedBins
    placed = true
    SCNTransaction.commit()
  }

  private static func material(_ color: UIColor) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = color
    material.isDoubleSided = true
    material.writesToDepthBuffer = false
    return material
  }

  private static func arc(start: Float, end: Float) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    var indices: [UInt16] = []
    let steps = max(4, Int((end - start) * 48))
    for index in 0...steps {
      let angle = start + (end - start) * Float(index) / Float(steps)
      for radius: Float in [0.994, 1.006] {
        vertices.append(SCNVector3(sin(angle) * radius, cos(angle) * radius, 0))
      }
      if index > 0 {
        let end = UInt16(index * 2)
        indices.append(contentsOf: [end - 2, end - 1, end, end - 1, end + 1, end])
      }
    }
    return SCNGeometry(sources: [.init(vertices: vertices)], elements: [.init(indices: indices, primitiveType: .triangles)])
  }
}
