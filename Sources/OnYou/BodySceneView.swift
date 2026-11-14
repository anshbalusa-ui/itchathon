import SceneKit
import SwiftUI

struct BodySceneCameraRequest: Equatable {
  enum Action: Equatable { case turn(Float), front, back, reset }
  let id = UUID()
  var action: Action
}

struct BodySceneView: UIViewRepresentable {
  var measurements: BodyMeasurements
  var scan: ScannedBodySource? = nil
  var wireframe: Bool = false
  var tryOn: TryOnResult? = nil
  var showingGarment = true
  var cameraRequest: BodySceneCameraRequest? = nil
  var isActive = true

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    context.coordinator.view = view
    view.scene = context.coordinator.scene
    view.backgroundColor = .clear
    view.antialiasingMode = .multisampling4X
    view.rendersContinuously = false
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
    let loading = context.coordinator.loadingIndicator
    loading.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(loading)
    NSLayoutConstraint.activate([
      loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      loading.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
    return view
  }

  static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
    view.isPlaying = false
    view.scene = nil
    view.pointOfView = nil
    view.delegate = nil
    coordinator.detach()
  }

  func updateUIView(_ view: SCNView, context: Context) {
    let c = context.coordinator
    let height = scan?.referenceHeightCM ?? measurements.height
    if let scan {
      if c.loadedScan != scan || c.scannedNode == nil {
        c.updateScan(scan)
        view.pointOfView = c.camera
      }
    } else if c.requestedMeasurements != measurements || c.loadedScan != nil {
      c.update(measurements)
      view.pointOfView = c.camera
    }
    c.updateTryOn(tryOn, showing: showingGarment)
    c.scene.isPaused = !isActive
    if let request = cameraRequest, request.id != c.lastCameraRequest {
      c.lastCameraRequest = request.id
      switch request.action {
      case .turn(let delta): c.turn(view, by: delta)
      case .front, .reset:
        c.angle = 0; c.positionCamera(angle: 0, height: Float(height / 100)); view.pointOfView = c.camera
      case .back:
        c.angle = .pi; c.positionCamera(angle: .pi, height: Float(height / 100)); view.pointOfView = c.camera
      }
    }
    view.defaultCameraController.target = SCNVector3(0, Float(height / 100) * 0.51, 0.035)
    c.wireframe = wireframe
    c.body.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
    c.updateAccessibility()
    view.accessibilityCustomActions = [
      UIAccessibilityCustomAction(name: "Rotate left") { _ in c.turn(view, by: -.pi / 6); return true },
      UIAccessibilityCustomAction(name: "Rotate right") { _ in c.turn(view, by: .pi / 6); return true },
      UIAccessibilityCustomAction(name: "Reset view") { _ in c.positionCamera(angle: 0, height: Float(height / 100)); view.pointOfView = c.camera; return true }
    ]
  }

  @MainActor final class Coordinator {
    var scene = SCNScene()
    var body = SCNNode()
    var shorts = SCNNode()
    var camera = SCNNode()
    var loadedScan: ScannedBodySource?
    var scannedNode: SCNNode?
    var measurements: BodyMeasurements?
    private(set) var requestedMeasurements: BodyMeasurements?
    private(set) var generationTask: Task<Void, Never>?
    weak var view: SCNView?
    let loadingIndicator = UIActivityIndicatorView(style: .medium)
    var wireframe = false
    var angle: Float = 0
    var loadedTryOnID: UUID?
    var garmentVisible = true
    var garmentNode: SCNNode?
    var failure: String?
    var lastCameraRequest: UUID?
    private var generationID = 0
    private var detached = false
    private var statusNode: SCNNode?

    init() {
      // The studio rig affects only the illustrative mannequin, never saved scans.
      body.categoryBitMask = 2
      shorts.categoryBitMask = 2
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
      ambient.light?.categoryBitMask = 1
      ambient.light?.intensity = 350
      ambient.light?.color = UIColor(white: 0.95, alpha: 1)
      scene.rootNode.addChildNode(ambient)
      let key = SCNNode()
      key.light = SCNLight()
      key.light?.type = .directional
      key.light?.categoryBitMask = 1
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
      rim.light?.categoryBitMask = 1
      rim.light?.intensity = 300
      rim.eulerAngles = SCNVector3(-0.2, 2.4, 0)
      scene.rootNode.addChildNode(rim)
      addStudioLight(.ambient, intensity: 220, color: UIColor(white: 0.94, alpha: 1))
      addStudioLight(.directional, intensity: 900,
        color: UIColor(red: 1, green: 0.98, blue: 0.95, alpha: 1),
        angles: SCNVector3(-0.45, -0.65, 0))
      addStudioLight(.directional, intensity: 320,
        color: UIColor(red: 0.88, green: 0.94, blue: 1, alpha: 1),
        angles: SCNVector3(-0.15, 0.95, 0))
      addStudioLight(.directional, intensity: 500,
        color: UIColor(white: 1, alpha: 1), angles: SCNVector3(-0.4, 2.6, 0))
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
    }

    private func addStudioLight(_ type: SCNLight.LightType, intensity: CGFloat,
                                color: UIColor, angles: SCNVector3 = SCNVector3Zero) {
      let node = SCNNode()
      let light = SCNLight()
      light.type = type
      light.categoryBitMask = 2
      light.intensity = intensity
      light.color = color
      node.light = light
      node.eulerAngles = angles
      scene.rootNode.addChildNode(node)
    }

    func update(_ values: BodyMeasurements) {
      guard !detached else { return }
      generationTask?.cancel()
      generationID += 1
      let requestID = generationID
      requestedMeasurements = values
      scannedNode?.removeFromParentNode()
      scannedNode = nil
      loadedScan = nil
      statusNode?.removeFromParentNode()
      statusNode = nil
      failure = nil
      loadingIndicator.startAnimating()
      updateAccessibility()
      generationTask = Task { [weak self] in
        do {
          let result = try await BodyModelGenerator.shared.generate(values)
          try Task.checkCancellation()
          guard let self, !self.detached, self.generationID == requestID else { return }
          self.body.geometry = self.geometry(result.body,
            color: UIColor(red: 0.72, green: 0.73, blue: 0.74, alpha: 1))
          self.shorts.geometry = self.geometry(result.shorts,
            color: UIColor(red: 0.22, green: 0.27, blue: 0.29, alpha: 1))
          self.body.geometry?.firstMaterial?.fillMode = self.wireframe ? .lines : .fill
          self.body.isHidden = false
          self.shorts.isHidden = false
          self.measurements = values
          self.positionCamera(angle: self.angle, height: Float(values.height / 100))
          self.view?.pointOfView = self.camera
          self.generationTask = nil
          self.loadingIndicator.stopAnimating()
          self.updateAccessibility()
          self.view?.setNeedsDisplay()
        } catch is CancellationError {
          // Replaced requests and detached scenes must never publish a model.
        } catch {
          guard let self, !self.detached, self.generationID == requestID else { return }
          self.generationTask = nil
          self.loadingIndicator.stopAnimating()
          self.failure = "The body model couldn’t be updated. Check your measurements."
          self.body.isHidden = true
          self.shorts.isHidden = true
          let label = SCNText(string: "Model unavailable", extrusionDepth: 0)
          label.font = .systemFont(ofSize: 0.08)
          label.firstMaterial?.diffuse.contents = UIColor.secondaryLabel
          let node = SCNNode(geometry: label)
          node.position = SCNVector3(-0.36, 0.9, 0)
          self.statusNode = node
          self.scene.rootNode.addChildNode(node)
          self.positionCamera(angle: 0, height: Float(values.height / 100))
          self.updateAccessibility()
          self.view?.setNeedsDisplay()
        }
      }
    }

    func updateAccessibility() {
      if let failure {
        view?.accessibilityValue = failure
      } else if loadedScan != nil {
        view?.accessibilityValue = "Saved textured avatar. Drag to rotate."
      } else if requestedMeasurements != measurements {
        view?.accessibilityValue = "Updating body model"
      } else if let values = measurements {
        view?.accessibilityValue = "Height \(values.height.formatted()) centimeters, chest \(values.chest.formatted()), waist \(values.waist.formatted()), hips \(values.hips.formatted())"
      }
    }

    func updateScan(_ source: ScannedBodySource) {
      generationTask?.cancel()
      generationTask = nil
      loadingIndicator.stopAnimating()
      generationID += 1
      requestedMeasurements = nil
      statusNode?.removeFromParentNode()
      statusNode = nil
      scannedNode?.removeFromParentNode()
      // Apply canonical yaw AFTER the saved scene's normalization transform.
      // Rotating the normalized root itself would rotate before its translation.
      let owner = SCNNode()
      owner.name = "avatar.normalized-owner"
      owner.addChildNode(source.scene.makeNode())
      scannedNode = owner
      scene.rootNode.addChildNode(owner)
      loadedScan = source
      body.isHidden = true; shorts.isHidden = true; failure = nil
      positionCamera(angle: 0,height: Float(source.referenceHeightCM/100))
    }

    func detach() {
      detached = true
      generationTask?.cancel()
      generationTask = nil
      loadingIndicator.stopAnimating()
      generationID += 1
      view = nil
      garmentNode?.removeFromParentNode(); garmentNode = nil
      scannedNode?.removeFromParentNode(); scannedNode = nil
      loadedScan = nil; loadedTryOnID = nil
      scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
    }

    func updateTryOn(_ result: TryOnResult?, showing: Bool) {
      if loadedTryOnID != result?.id {
        garmentNode?.removeFromParentNode()
        garmentNode = result?.garment.makeNode()
        loadedTryOnID = result?.id
        if let garmentNode { scene.rootNode.addChildNode(garmentNode) }
      }
      garmentVisible = showing
      garmentNode?.isHidden = !showing
      scannedNode?.eulerAngles.y = result?.bodyYaw ?? 0
    }


    func positionCamera(angle: Float, height: Float) {
      let distance = max(2.8, height * 1.9)
      camera.position = SCNVector3(sin(angle) * distance, height * 0.54, cos(angle) * distance)
      camera.look(at: SCNVector3(0, height * 0.51, 0.035))
    }

    func turn(_ view: SCNView, by delta: Float) {
      let current = view.pointOfView?.presentation.simdWorldPosition ?? camera.simdWorldPosition
      let height = Float((loadedScan?.referenceHeightCM ?? measurements?.height ?? 175) / 100)
      let target = SIMD3<Float>(0, height * 0.51, 0.035)
      let distance = max(0.2, simd_length(SIMD2(current.x - target.x, current.z - target.z)))
      angle = atan2(current.x - target.x, current.z - target.z) + delta
      camera.simdWorldPosition = SIMD3(sin(angle) * distance + target.x, current.y, cos(angle) * distance + target.z)
      camera.look(at: SCNVector3(target.x,target.y,target.z))
      view.pointOfView = camera
    }

    private func geometry(_ mesh: RendererMesh, color: UIColor) -> SCNGeometry {
      let data = mesh.vertices.withUnsafeBytes { Data($0) }
      let stride = MemoryLayout<RendererVertex>.stride
      let positions = SCNGeometrySource(data: data, semantic: .vertex,
        vectorCount: mesh.vertices.count, usesFloatComponents: true, componentsPerVector: 3,
        bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: stride)
      let normals = SCNGeometrySource(data: data, semantic: .normal,
        vectorCount: mesh.vertices.count, usesFloatComponents: true, componentsPerVector: 3,
        bytesPerComponent: MemoryLayout<Float>.size,
        dataOffset: MemoryLayout<RendererVertex>.offset(of: \.normal)!, dataStride: stride)
      let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
      let geometry = SCNGeometry(sources: [positions, normals], elements: [element])
      let material = SCNMaterial()
      material.lightingModel = .physicallyBased
      material.diffuse.contents = color
      material.roughness.contents = 0.68
      material.metalness.contents = 0
      geometry.materials = [material]
      return geometry
    }
  }
}

struct ScannedBodySource: Equatable {
  var url: URL
  var scene: PreparedAvatarScene
  var referenceHeightCM: Double { scene.calibration.referenceHeightCM }
  static func == (a: Self,b: Self) -> Bool { a.url == b.url && a.scene === b.scene }
}

