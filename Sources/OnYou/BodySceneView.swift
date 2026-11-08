import SceneKit
import SwiftUI

struct BodySceneView: UIViewRepresentable {
  var measurements: BodyMeasurements
  var scan: ScannedBodySource? = nil
  var wireframe: Bool = false
  var tryOn: TryOnResult? = nil
  var showingGarment = true

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
    view.accessibilityHint = "Drag to rotate. Pinch to zoom."
    view.accessibilityIdentifier = "body.scene"
    return view
  }

  func updateUIView(_ view: SCNView, context: Context) {
    let c = context.coordinator
    let height = scan?.referenceHeightCM ?? measurements.height
    if let scan {
      if c.loadedScan != scan {
        c.updateScan(scan)
        view.pointOfView = c.camera
      }
    } else if c.measurements != measurements || c.loadedScan != nil {
      c.update(measurements)
      view.pointOfView = c.camera
    }
    c.updateTryOn(tryOn, showing: showingGarment)
    view.defaultCameraController.target = SCNVector3(0, Float(height / 100) * 0.51, 0.035)
    c.body.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
    view.accessibilityValue = scan != nil ? "Captured textured avatar. Drag to rotate."
      : "Height \(measurements.height.formatted()) centimeters, chest \(measurements.chest.formatted()), waist \(measurements.waist.formatted()), hips \(measurements.hips.formatted())"
    view.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "Rotate left") { _ in c.turn(view, by: -.pi / 6); return true },
      UIAccessibilityCustomAction(name: "Rotate right") { _ in c.turn(view, by: .pi / 6); return true },
      UIAccessibilityCustomAction(name: "Reset view") { _ in c.positionCamera(angle: 0, height: Float(height / 100)); view.pointOfView = c.camera; return true }
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
    var loadedScan: ScannedBodySource?
    var scannedNode: SCNNode?
    var measurements: BodyMeasurements?
    var angle: Float = 0
    var loadedTryOnID: UUID?
    var garmentVisible = true
    var garmentNode: SCNNode?
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
        scannedNode?.removeFromParentNode()
        scannedNode = nil
        loadedScan = nil
        body.isHidden = false
        shorts.isHidden = false
        failure = nil
        body.geometry = geometry(try kernel.shape(assets.body, to: values), color: UIColor(red: 0.66, green: 0.57, blue: 0.48, alpha: 1))
        shorts.geometry = geometry(try kernel.shape(assets.shorts, to: values), color: UIColor(red: 0.22, green: 0.27, blue: 0.29, alpha: 1))
        measurements = values
        positionCamera(angle: angle, height: Float(values.height / 100))
      } catch {
        failure = "The body model couldn’t be updated. Check your measurements."
      }
    }

    func updateScan(_ source: ScannedBodySource) {
      scannedNode?.removeFromParentNode()
      scannedNode = nil
      body.isHidden = true
      shorts.isHidden = true
      loadedScan = source
      do {
        let result = try ScannedAvatarGeometry.load(url: source.url, referenceHeightCM: source.referenceHeightCM)
        scannedNode = result.node
        scene.rootNode.addChildNode(result.node)
        failure = nil
        positionCamera(angle: 0, height: Float(source.referenceHeightCM / 100))
      } catch {
        failure = "The captured avatar couldn’t be opened. Retake or delete the scan from the Body tab."
        let text = SCNText(string: "Scan unavailable", extrusionDepth: 0)
        text.font = .systemFont(ofSize: 0.07)
        text.firstMaterial?.diffuse.contents = UIColor.secondaryLabel
        let node = SCNNode(geometry: text)
        node.position = SCNVector3(-0.32, 0.9, 0)
        scannedNode = node
        scene.rootNode.addChildNode(node)
      }
    }

    func updateTryOn(_ result: TryOnResult?, showing: Bool) {
      if loadedTryOnID != result?.id || garmentVisible != showing {
        garmentNode?.removeFromParentNode()
        garmentNode = nil
        loadedTryOnID = result?.id
        garmentVisible = showing
        scannedNode?.eulerAngles.y = result?.bodyYaw ?? 0
        if showing, let result, let node = Self.garmentNode(for: result) {
          garmentNode = node
          scene.rootNode.addChildNode(node)
        }
      }
    }

    private static func garmentNode(for result: TryOnResult) -> SCNNode? {
      let mesh = result.shape.mesh
      guard mesh.positions.count < 65535, mesh.positions.count == mesh.textureCoordinates.count,
            !mesh.front.isEmpty, !mesh.back.isEmpty else { return nil }
      let vertices = mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) }
      let coords = mesh.textureCoordinates.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
      let geometry = SCNGeometry(sources: [.init(vertices: vertices), .init(textureCoordinates: coords)],
                                 elements: [.init(indices: mesh.front.map { UInt16($0) }, primitiveType: .triangles),
                                            .init(indices: mesh.back.map { UInt16($0) }, primitiveType: .triangles)])
      let front = SCNMaterial()
      front.lightingModel = .constant
      front.diffuse.contents = UIImage(contentsOfFile: result.photoURL.path)
      front.isDoubleSided = true
      let back = SCNMaterial()
      back.lightingModel = .constant
      back.diffuse.contents = UIColor(red: CGFloat(result.backColor.x), green: CGFloat(result.backColor.y), blue: CGFloat(result.backColor.z), alpha: 1)
      back.isDoubleSided = true
      geometry.materials = [front, back]
      return SCNNode(geometry: geometry)
    }

    func positionCamera(angle: Float, height: Float) {
      let distance = max(2.8, height * 1.9)
      camera.position = SCNVector3(sin(angle) * distance, height * 0.54, cos(angle) * distance)
      camera.look(at: SCNVector3(0, height * 0.51, 0.035))
    }

    func turn(_ view: SCNView, by delta: Float) {
      angle += delta
      positionCamera(angle: angle, height: Float((loadedScan?.referenceHeightCM ?? measurements?.height ?? 175) / 100))
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

struct ScannedBodySource: Equatable {
  var url: URL
  var referenceHeightCM: Double
}

struct ScannedAvatarPreview: View {
  var url: URL
  var referenceHeightCM: Double

  var body: some View {
    BodySceneView(measurements: .example, scan: ScannedBodySource(url: url, referenceHeightCM: referenceHeightCM))
      .background(Color(uiColor: .secondarySystemGroupedBackground))
  }
}
