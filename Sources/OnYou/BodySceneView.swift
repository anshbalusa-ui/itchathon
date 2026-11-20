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
  var reduceMotion = false

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> SCNView {
    let view = SCNView()
    view.scene = context.coordinator.scene
    view.backgroundColor = .clear
    view.antialiasingMode = .multisampling4X
    view.rendersContinuously = false
    view.allowsCameraControl = true
    view.defaultCameraController.interactionMode = .orbitTurntable
    view.defaultCameraController.inertiaEnabled = !reduceMotion
    view.defaultCameraController.minimumHorizontalAngle = -360
    view.defaultCameraController.maximumHorizontalAngle = 360
    view.defaultCameraController.target = SCNVector3(0, 0.9, 0)
    view.defaultCameraController.minimumVerticalAngle = -25
    view.defaultCameraController.maximumVerticalAngle = 30
    view.cameraControlConfiguration.allowsTranslation = false
    view.cameraControlConfiguration.autoSwitchToFreeCamera = false
    view.pointOfView = context.coordinator.camera
    context.coordinator.renderView = view
    view.accessibilityCustomActions = context.coordinator.makeAccessibilityActions(for: view)
    context.coordinator.observeCameraGestures(in: view)
    view.isAccessibilityElement = true
    view.accessibilityLabel = "Body model"
    view.accessibilityHint = "Drag to rotate. Pinch to zoom."
    view.accessibilityIdentifier = "body.scene"
    return view
  }

  static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
    view.isPlaying = false
    coordinator.stopObservingCameraGestures(in: view)
    view.accessibilityCustomActions = nil
    view.scene = nil
    view.pointOfView = nil
    view.delegate = nil
    coordinator.detach()
  }

  func updateUIView(_ view: SCNView, context: Context) {
    let c = context.coordinator
    let height = scan?.referenceHeightCM ?? measurements.height
    c.currentHeight = Float(height / 100)
    c.isActive = isActive
    if let scan {
      if c.loadedScan != scan || c.scannedNode == nil {
        c.updateScan(scan)
        view.pointOfView = c.camera
      }
    } else if c.measurements != measurements || c.loadedScan != nil {
      c.update(measurements)
      view.pointOfView = c.camera
    }
    c.updateTryOn(tryOn, showing: showingGarment, reduceMotion: reduceMotion)
    c.scene.isPaused = !isActive
    view.isPlaying = isActive && (c.isSettling || c.isCameraTransitioning)
    if let request = cameraRequest, request.id != c.lastCameraRequest {
      c.lastCameraRequest = request.id
      switch request.action {
      case .turn(let delta): c.turn(view, by: delta)
      case .front: c.inspect(view, angle: 0, height: c.currentHeight)
      case .back: c.inspect(view, angle: .pi, height: c.currentHeight)
      case .reset: c.resetCamera(view, height: c.currentHeight)
      }
    }
    view.defaultCameraController.inertiaEnabled = !reduceMotion
    view.defaultCameraController.target = SCNVector3(0, c.currentHeight * 0.51, 0.035)
    c.body.geometry?.firstMaterial?.fillMode = wireframe ? .lines : .fill
    let value = scan != nil ? "Textured body scan. Drag to rotate. Pinch to zoom."
      : "Height \(measurements.height.formatted()) centimeters, chest \(measurements.chest.formatted()), waist \(measurements.waist.formatted()), hips \(measurements.hips.formatted())"
    if view.accessibilityValue != value { view.accessibilityValue = value }
    if c.failure != nil { view.accessibilityValue = c.failure }
  }

  @MainActor final class Coordinator: NSObject {
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
    var lastCameraRequest: UUID?
    private(set) var isSettling = false
    private(set) var isCameraTransitioning = false
    var isActive = true
    var currentHeight: Float = 1.75
    var reduceMotion = false
    weak var renderView: SCNView?
    private var settlementFinished = false
    private var settlementGeneration = UUID()
    private var cameraTransitionGeneration = UUID()

    func makeAccessibilityActions(for view: SCNView) -> [UIAccessibilityCustomAction] {
      [
        UIAccessibilityCustomAction(name: "Rotate left") { [weak self, weak view] _ in
          guard let self, let view else { return false }
          self.turn(view, by: -.pi / 6)
          return true
        },
        UIAccessibilityCustomAction(name: "Rotate right") { [weak self, weak view] _ in
          guard let self, let view else { return false }
          self.turn(view, by: .pi / 6)
          return true
        },
        UIAccessibilityCustomAction(name: "Zoom in") { [weak self, weak view] _ in
          guard let self, let view else { return false }
          self.zoom(view, factor: 0.8)
          return true
        },
        UIAccessibilityCustomAction(name: "Zoom out") { [weak self, weak view] _ in
          guard let self, let view else { return false }
          self.zoom(view, factor: 1.25)
          return true
        },
        UIAccessibilityCustomAction(name: "Reset view") { [weak self, weak view] _ in
          guard let self, let view else { return false }
          self.resetCamera(view, height: self.currentHeight)
          return true
        }
      ]
    }
    func observeCameraGestures(in view: SCNView) {
      for gesture in view.gestureRecognizers ?? [] where
        gesture is UIPanGestureRecognizer || gesture is UIPinchGestureRecognizer || gesture is UIRotationGestureRecognizer {
        gesture.addTarget(self, action: #selector(cameraGestureChanged(_:)))
      }
    }

    func stopObservingCameraGestures(in view: SCNView) {
      for gesture in view.gestureRecognizers ?? [] {
        gesture.removeTarget(self, action: #selector(cameraGestureChanged(_:)))
      }
    }

    @objc private func cameraGestureChanged(_ gesture: UIGestureRecognizer) {
      guard gesture.state == .began || gesture.state == .changed else { return }
      interruptCameraTransition()
    }

    func interruptCameraTransition() {
      guard isCameraTransitioning else { return }
      let position = camera.presentation.position
      let orientation = camera.presentation.orientation
      camera.removeAllAnimations()
      camera.position = position
      camera.orientation = orientation
      angle = atan2(position.x, position.z - 0.035)
      cameraTransitionGeneration = UUID()
      isCameraTransitioning = false
      renderView?.isPlaying = isActive && isSettling
    }
    private var attemptedExampleLoad = false
    private var assets: HumanShowcaseMeshes?
    private var kernel: BodyShapeKernel?

    override init() {
      super.init()
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
    }

    private func prepareExampleIfNeeded() {
      guard !attemptedExampleLoad else { return }
      attemptedExampleLoad = true
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
      prepareExampleIfNeeded()
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
      settlementGeneration = UUID()
      cameraTransitionGeneration = UUID()
      garmentNode?.removeAction(forKey: "tryon.settle")
      garmentNode?.removeFromParentNode(); garmentNode = nil
      isSettling = false; isCameraTransitioning = false; settlementFinished = false; renderView = nil
      scannedNode?.removeFromParentNode(); scannedNode = nil
      loadedScan = nil; loadedTryOnID = nil
      scene.rootNode.childNodes.forEach { $0.removeFromParentNode() }
    }

    func updateTryOn(_ result: TryOnResult?, showing: Bool, reduceMotion: Bool = false) {
      self.reduceMotion = reduceMotion
      if reduceMotion && isCameraTransitioning {
        cameraTransitionGeneration = UUID()
        camera.removeAllAnimations()
        isCameraTransitioning = false
      }
      if loadedTryOnID != result?.id {
        settlementGeneration = UUID()
        garmentNode?.removeAction(forKey: "tryon.settle")
        garmentNode?.removeFromParentNode()
        garmentNode = result?.garment.makeNode()
        loadedTryOnID = result?.id
        isSettling = false; settlementFinished = false
        if let garmentNode { scene.rootNode.addChildNode(garmentNode) }
      }
      garmentVisible = showing
      scannedNode?.eulerAngles.y = result?.bodyYaw ?? 0
      garmentNode?.isHidden = !showing
      guard let node = garmentNode else { return }
      if reduceMotion {
        node.removeAction(forKey: "tryon.settle")
        node.position = SCNVector3(0, 0, 0)
        isSettling = false; settlementFinished = true
        return
      }
      if !showing {
        if isSettling {
          settlementGeneration = UUID()
          node.removeAction(forKey: "tryon.settle")
          node.position = SCNVector3(0, 0, 0)
          isSettling = false; settlementFinished = true
        }
        return
      }
      guard !settlementFinished, !isSettling else { return }
      let fall = SCNAction.move(to: SCNVector3(0, 0.004, 0), duration: 0.56)
      fall.timingMode = .easeInEaseOut
      let settle = SCNAction.move(to: SCNVector3(0, 0, 0), duration: 0.24)
      settle.timingMode = .easeOut
      let token = UUID()
      settlementGeneration = token
      node.position = SCNVector3(0, 0.075, 0)
      isSettling = true
      node.runAction(.sequence([fall, settle]), forKey: "tryon.settle") { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.settlementGeneration == token else { return }
          self.isSettling = false
          self.settlementFinished = true
          self.renderView?.isPlaying = self.isActive && self.isCameraTransitioning
        }
      }
    }


    func positionCamera(angle: Float, height: Float) {
      self.angle = angle
      let distance = max(2.8, height * 1.9)
      camera.position = SCNVector3(sin(angle) * distance, height * 0.54, cos(angle) * distance + 0.035)
      camera.look(at: SCNVector3(0, height * 0.51, 0.035))
    }

    func inspect(_ view: SCNView, angle: Float, height: Float) {
      let target = SIMD3<Float>(0, height * 0.51, 0.035)
      let current = cameraPosition(in: view)
      let offset = current - target
      let distance = max(0.2, simd_length(offset))
      let pitch = atan2(offset.y, simd_length(SIMD2(offset.x, offset.z)))
      let horizontal = distance * cos(pitch)
      moveCamera(view, angle: angle, height: height, distance: horizontal, y: target.y + distance * sin(pitch))
    }

    func resetCamera(_ view: SCNView, height: Float) {
      let distance = max(2.8, height * 1.9)
      moveCamera(view, angle: 0, height: height, distance: distance, y: height * 0.54)
    }

    func zoom(_ view: SCNView, factor: Float) {
      interruptCameraTransition()
      let target = SIMD3<Float>(0, currentHeight * 0.51, 0.035)
      let offset = (view.pointOfView?.simdWorldPosition ?? camera.simdWorldPosition) - target
      let oldDistance = simd_length(offset)
      guard factor.isFinite, factor > 0, oldDistance.isFinite, oldDistance > 0.01 else { return }
      let distance = min(currentHeight * 3.5, max(currentHeight * 0.65, oldDistance * factor))
      let scaled = offset * (distance / oldDistance)
      moveCamera(view, angle: atan2(scaled.x, scaled.z), height: currentHeight,
                 distance: simd_length(SIMD2(scaled.x, scaled.z)), y: target.y + scaled.y)
    }

    private func moveCamera(_ view: SCNView, angle: Float, height: Float, distance: Float, y: Float) {
      self.angle = angle
      let target = SCNVector3(0, height * 0.51, 0.035)
      let position = SCNVector3(sin(angle) * distance, y, cos(angle) * distance + target.z)
      guard !reduceMotion else {
        camera.removeAllAnimations()
        cameraTransitionGeneration = UUID()
        isCameraTransitioning = false
        camera.position = position
        camera.look(at: target)
        view.pointOfView = camera
        view.isPlaying = isActive && isSettling
        return
      }
      let current = view.pointOfView ?? camera
      let source = isCameraTransitioning ? current.presentation : current
      let currentPosition = source.position
      let currentOrientation = source.orientation
      camera.removeAllAnimations()
      camera.position = currentPosition
      camera.orientation = currentOrientation
      let token = UUID()
      cameraTransitionGeneration = token
      isCameraTransitioning = true
      view.isPlaying = isActive
      SCNTransaction.begin()
      SCNTransaction.animationDuration = 0.32
      SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      SCNTransaction.completionBlock = { [weak self] in
        Task { @MainActor [weak self] in
          guard let self, self.cameraTransitionGeneration == token else { return }
          self.isCameraTransitioning = false
          self.renderView?.isPlaying = self.isActive && self.isSettling && self.renderView?.scene?.isPaused == false
        }
      }
      camera.position = position
      camera.look(at: target)
      SCNTransaction.commit()
      view.pointOfView = camera
    }

    func turn(_ view: SCNView, by delta: Float) {
      let height = currentHeight
      let target = SIMD3<Float>(0, height * 0.51, 0.035)
      let current = cameraPosition(in: view)
      let offset = current - target
      let distance = max(0.2, simd_length(offset))
      let pitch = atan2(offset.y, simd_length(SIMD2(offset.x, offset.z)))
      let horizontal = distance * cos(pitch)
      let angle = atan2(offset.x, offset.z) + delta
      moveCamera(view, angle: angle, height: height, distance: horizontal, y: target.y + distance * sin(pitch))
    }

    private func cameraPosition(in view: SCNView) -> SIMD3<Float> {
      let node = view.pointOfView ?? camera
      return isCameraTransitioning ? node.presentation.simdWorldPosition : node.simdWorldPosition
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
  var scene: PreparedAvatarScene
  var referenceHeightCM: Double { scene.calibration.referenceHeightCM }
  static func == (a: Self,b: Self) -> Bool { a.url == b.url && a.scene === b.scene }
}
