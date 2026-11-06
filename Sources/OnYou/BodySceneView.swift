import SceneKit
import SwiftUI

struct BodySceneView: UIViewRepresentable {
  var measurements: BodyMeasurements
  var angle: Float
  var reset: Int
  var wireframe: Bool = false

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = context.coordinator.scene
    view.backgroundColor = .clear
    view.antialiasingMode = .multisampling4X
    view.allowsCameraControl = true
    view.defaultCameraController.interactionMode = .orbitTurntable
    view.defaultCameraController.inertiaEnabled = false
    view.defaultCameraController.target = SCNVector3(0, 0.9, 0)
    view.defaultCameraController.minimumVerticalAngle = -25
    view.defaultCameraController.maximumVerticalAngle = 30
    view.cameraControlConfiguration.allowsTranslation = false
    view.cameraControlConfiguration.autoSwitchToFreeCamera = false
    view.pointOfView = context.coordinator.camera
    view.isAccessibilityElement = true
    view.accessibilityLabel = "Body model"
    view.accessibilityHint = "Drag to rotate. Pinch to zoom. View controls are below the model."
    view.accessibilityIdentifier = "body.scene"
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    let c = context.coordinator
    if c.measurements != measurements {
      c.update(measurements)
      view.defaultCameraController.target = SCNVector3(0, Float(measurements.height / 100) * 0.51, 0.035)
    }
    c.body.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
    if c.reset != reset || c.angle != angle {
      c.reset = reset
      c.angle = angle
      c.positionCamera(angle: angle, height: Float(measurements.height / 100))
      view.pointOfView = c.camera
    }
    view.accessibilityValue = "Height \(measurements.height.formatted()) centimeters, chest \(measurements.chest.formatted()), waist \(measurements.waist.formatted()), hips \(measurements.hips.formatted())"
    view.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "Rotate left") { _ in c.turn(view, by: -.pi / 6); return true },
      UIAccessibilityCustomAction(name: "Rotate right") { _ in c.turn(view, by: .pi / 6); return true },
      UIAccessibilityCustomAction(name: "Reset view") { _ in c.positionCamera(angle: 0, height: Float(measurements.height / 100)); view.pointOfView = c.camera; return true }
    ]
    if c.failure != nil {
      view.accessibilityValue = c.failure
    }
  }

  @MainActor final class Coordinator {
    var scene = SCNScene()
    var body = SCNNode()
    var shorts = SCNNode()
    var camera = SCNNode()
    var measurements: BodyMeasurements?
    var angle: Float = 0
    var reset = -1
    var failure: String?
    private var assets: HumanShowcaseMeshes?
    private var kernel: BodyShapeKernel?

    init() {
      scene.rootNode.addChildNode(body)
      scene.rootNode.addChildNode(shorts)
      camera.camera = SCNCamera()
      camera.camera?.fieldOfView = 33
      camera.camera?.zNear = 0.05
      camera.camera?.zFar = 30
      camera.camera?.wantsHDR = false
      camera.camera?.wantsExposureAdaptation = false
      scene.rootNode.addChildNode(camera)
      let ambient = SCNNode()
      ambient.light = SCNLight()
      ambient.light?.type = .ambient
      ambient.light?.intensity = 350
      ambient.light?.color = UIColor(white: 0.95, alpha: 1)
      scene.rootNode.addChildNode(ambient)
      let key = SCNNode()
      key.light = SCNLight()
      key.light?.type = .directional
      key.light?.intensity = 900
      key.eulerAngles = SCNVector3(-0.5, -0.6, 0)
      key.light?.castsShadow = true
      key.light?.shadowRadius = 12
      key.light?.shadowColor = UIColor.black.withAlphaComponent(0.12)
      key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
      scene.rootNode.addChildNode(key)
      let rim = SCNNode()
      rim.light = SCNLight()
      rim.light?.type = .directional
      rim.light?.intensity = 300
      rim.eulerAngles = SCNVector3(-0.2, 2.4, 0)
      scene.rootNode.addChildNode(rim)
      let shadowImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { context in
        let colors = [UIColor.black.withAlphaComponent(0.16).cgColor, UIColor.clear.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
          context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                               endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
      }
      let shadow = SCNPlane(width: 0.85, height: 0.55)
      shadow.firstMaterial?.lightingModel = .constant
      shadow.firstMaterial?.diffuse.contents = shadowImage
      shadow.firstMaterial?.writesToDepthBuffer = false
      let shadowNode = SCNNode(geometry: shadow)
      shadowNode.eulerAngles.x = -.pi / 2
      shadowNode.position.y = -0.005
      scene.rootNode.addChildNode(shadowNode)
      do {
        let loaded = try HumanShowcaseAssets.load()
        assets = loaded
        kernel = try BodyShapeKernel(reference: loaded.body)
      } catch {
        failure = "The body model couldn’t be opened. Close and reopen this screen to try again."
        let label = SCNText(string: "Model unavailable", extrusionDepth: 0)
        label.font = .systemFont(ofSize: 0.08)
        label.firstMaterial?.diffuse.contents = UIColor.secondaryLabel
        let node = SCNNode(geometry: label)
        node.position = SCNVector3(-0.36, 0.9, 0)
        scene.rootNode.addChildNode(node)
      }
    }

    func update(_ values: BodyMeasurements) {
      guard let assets, let kernel else { return }
      do {
        body.geometry = geometry(try kernel.shape(assets.body, to: values), color: UIColor(red: 0.66, green: 0.57, blue: 0.48, alpha: 1))
        shorts.geometry = geometry(try kernel.shape(assets.shorts, to: values), color: UIColor(red: 0.22, green: 0.27, blue: 0.29, alpha: 1))
        measurements = values
        positionCamera(angle: angle, height: Float(values.height / 100))
      } catch {
        failure = "The body model couldn’t be updated. Check your measurements."
      }
    }

    func positionCamera(angle: Float, height: Float) {
      let distance = max(2.8, height * 1.9)
      camera.position = SCNVector3(sin(angle) * distance, height * 0.54, cos(angle) * distance)
      camera.look(at: SCNVector3(0, height * 0.51, 0.035))
    }

    func turn(_ view: SCNView, by delta: Float) {
      angle += delta
      positionCamera(angle: angle, height: Float((measurements?.height ?? 175) / 100))
      view.pointOfView = camera
    }

    private func geometry(_ mesh: RendererMesh, color: UIColor) -> SCNGeometry {
      let vertices = mesh.vertices.map { SCNVector3($0.position.x, $0.position.y, $0.position.z) }
      let normals = mesh.vertices.map { SCNVector3($0.normal.x, $0.normal.y, $0.normal.z) }
      let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
      let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(normals: normals)], elements: [element])
      let material = SCNMaterial()
      material.lightingModel = .physicallyBased
      material.diffuse.contents = color
      material.roughness.contents = 0.72
      material.metalness.contents = 0
      geometry.materials = [material]
      return geometry
    }
  }
}
